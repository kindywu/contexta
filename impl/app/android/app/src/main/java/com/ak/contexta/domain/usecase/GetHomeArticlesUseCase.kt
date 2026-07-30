package com.ak.contexta.domain.usecase

import com.ak.contexta.domain.generation.categoryToDifficulty
import com.ak.contexta.domain.model.Article
import com.ak.contexta.domain.model.ArticleStatus
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

/**
 * 从 HomeViewModel 提取的文章过滤和排序逻辑。
 * 领域规则：按用户难度匹配文章，不足时返回全部已生成文章。
 */
@Singleton
class GetHomeArticlesUseCase @Inject constructor() {

    /**
     * 过滤并排序当前批次的文章。
     *
     * @param articles 批次所有文章
     * @param userDifficulty 用户当前难度等级
     * @param displayLimit 每批展示数量
     * @return 过滤排序后的文章列表
     */
    operator fun invoke(
        articles: List<Article>,
        userDifficulty: String,
        displayLimit: Int
    ): List<Article> {
        val matching = articles
            .filter { it.status != ArticleStatus.PENDING }
            .filter { categoryToDifficulty(it.contentCategory) == userDifficulty }
            .sortedBy { it.orderIndex }
            .take(displayLimit)

        return if (matching.isNotEmpty()) {
            matching
        } else {
            articles
                .filter { it.status != ArticleStatus.PENDING }
                .sortedBy { it.orderIndex }
                .take(displayLimit)
        }
    }
}
