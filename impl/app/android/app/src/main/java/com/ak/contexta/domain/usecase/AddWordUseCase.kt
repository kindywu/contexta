package com.ak.contexta.domain.usecase

import com.ak.contexta.domain.LlmClient
import com.ak.contexta.domain.error.LlmFatalException
import com.ak.contexta.domain.error.LlmRecoverableExhaustedException
import com.ak.contexta.domain.error.PipelineBlockingException
import com.ak.contexta.domain.generation.buildWordLookupSystemPrompt
import com.ak.contexta.domain.generation.buildWordLookupUserPrompt
import com.ak.contexta.domain.generation.parseWordLlmResponse
import com.ak.contexta.domain.model.WordDetail
import com.ak.contexta.domain.repository.StatsRepository
import com.ak.contexta.domain.repository.VocabularyRepository
import com.ak.contexta.domain.repository.WordRepository
import javax.inject.Inject
import javax.inject.Singleton

/**
 * 手动录入单词：用户输入英文单词，加入词库（word 表）和生词库（vocabulary_entry 表）。
 *
 * 本地没有词典，因此词库中不存在的单词通过 LLM 生成音标、释义与例句（复用阅读页的
 * 查词提示词与解析器，保证输出结构一致）。
 *
 * **流程：**
 * 1. 归一化 + 校验输入（仅英文字母/空格/连字符/撇号，长度上限）
 * 2. 本地词库检查（LRU 缓存 + Room，不触发 LLM）——[WordRepository.findLocal]
 *    - 命中：直接复用已有释义；若该词不在生词库则加入（[VocabularyRepository.addWord]）
 *    - 未命中：进入第 3 步
 * 3. 调用 LLM 生成单词详情 → 解析 → [WordRepository.saveLlmResult] 写入词库 →
 *    [VocabularyRepository.addWord] 加入生词库
 * 4. 无论命中与否，成功加入生词库时记录统计（[StatsRepository.recordWordAdded]）
 *
 * **错误处理**（与文章生成管道同一套错误分类）：
 * - [LlmFatalException] → 服务级不可恢复（鉴权/内容策略）
 * - [LlmRecoverableExhaustedException] → 网络等可恢复错误耗尽重试
 * - [PipelineBlockingException] → 结构性错误
 * - LLM 响应无法解析出有效释义 → 提示检查拼写
 */
@Singleton
class AddWordUseCase @Inject constructor(
    private val wordRepository: WordRepository,
    private val vocabularyRepository: VocabularyRepository,
    private val statsRepository: StatsRepository,
    private val llmClient: LlmClient
) {

    /** 录入过程所处阶段，供 UI 展示进度文案。 */
    enum class Stage { CHECKING_LOCAL, GENERATING }

    sealed interface AddWordResult {
        /** 词库中原本不存在，LLM 生成并加入生词库成功 */
        data class Success(val detail: WordDetail, val addedToVocabulary: Boolean) : AddWordResult

        /** 词库中已存在（本地命中，未调 LLM） */
        data class AlreadyExists(val detail: WordDetail, val addedToVocabulary: Boolean) : AddWordResult

        data class InvalidInput(val message: String) : AddWordResult

        data class Failed(val message: String) : AddWordResult
    }

    suspend operator fun invoke(
        rawInput: String,
        onStage: (Stage) -> Unit = {}
    ): AddWordResult {
        val normalized = WordRepository.normalize(rawInput)
        validate(normalized)?.let { return AddWordResult.InvalidInput(it) }

        // 1. 本地词库检查：命中则不调 LLM
        onStage(Stage.CHECKING_LOCAL)
        wordRepository.findLocal(normalized)?.let { existing ->
            val added = if (existing.isInVocabulary) {
                false
            } else {
                addToVocabulary(existing.wordId)
            }
            return AddWordResult.AlreadyExists(existing, addedToVocabulary = added)
        }

        // 2. LLM 生成
        onStage(Stage.GENERATING)
        return try {
            val llmResult = llmClient.call(
                buildWordLookupSystemPrompt(),
                buildWordLookupUserPrompt(normalized)
            )
            val parsed = parseWordLlmResponse(llmResult.content)
            if (parsed == null) {
                AddWordResult.Failed("AI 未能识别该单词的释义，请检查拼写后重试")
            } else {
                val detail = wordRepository.saveLlmResult(
                    spellingDisplay = parsed.spellingDisplay,
                    phoneticIpa = parsed.phoneticIpa,
                    senses = parsed.allSenses,
                    normalized = normalized
                )
                val added = addToVocabulary(detail.wordId)
                AddWordResult.Success(detail, addedToVocabulary = added)
            }
        } catch (e: LlmFatalException) {
            AddWordResult.Failed("AI 服务暂不可用（${e.message ?: "未知错误"}），请稍后重试")
        } catch (e: LlmRecoverableExhaustedException) {
            AddWordResult.Failed("网络不稳定，AI 多次重试后仍未成功，请稍后重试")
        } catch (e: PipelineBlockingException) {
            AddWordResult.Failed("系统暂时无法生成单词信息，请稍后重试")
        } catch (e: Exception) {
            AddWordResult.Failed("录入失败，请稍后重试")
        }
    }

    /** 加入生词库并记录统计，返回是否新增（false = 已在生词库）。 */
    private suspend fun addToVocabulary(wordId: Long): Boolean {
        val entryId = vocabularyRepository.addWord(wordId)
        if (entryId != null) statsRepository.recordWordAdded()
        return entryId != null
    }

    companion object {
        private val WORD_PATTERN = Regex("^[A-Za-z][A-Za-z'\\- ]*$")

        const val MAX_INPUT_LENGTH = 50

        /** 返回 null 表示校验通过；否则返回用户可读的失败原因。 */
        fun validate(normalized: String): String? {
            if (normalized.isBlank()) return "请输入要录入的单词"
            if (normalized.length > MAX_INPUT_LENGTH) return "单词过长（最多 $MAX_INPUT_LENGTH 个字符）"
            if (!WORD_PATTERN.matches(normalized)) return "只能输入英文字母、空格、连字符和撇号"
            if (normalized.none { it.isLetter() }) return "至少包含一个英文字母"
            return null
        }
    }
}
