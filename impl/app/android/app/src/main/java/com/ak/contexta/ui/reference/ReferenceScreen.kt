package com.ak.contexta.ui.reference

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.ak.contexta.ui.theme.Accent
import com.ak.contexta.ui.theme.AccentOn
import com.ak.contexta.ui.theme.Background
import com.ak.contexta.ui.theme.Foreground
import com.ak.contexta.ui.theme.ForegroundSecondary
import com.ak.contexta.ui.theme.Meta
import com.ak.contexta.ui.theme.Muted
import com.ak.contexta.ui.theme.Surface
import com.ak.contexta.ui.theme.SurfaceWarm

data class AlphabetItem(
    val char: String,
    val phone: String,
    val example: String,
    val cn: String
)

data class PhonicsItem(
    val phone: String,
    val example: String,
    val full: String
)

data class GrammarItem(
    val name: String,
    val explanation: String,
    val chineseExplanation: String,
    val examples: List<Pair<String, String>>
)

@Composable
fun ReferenceScreen() {
    var selectedTab by remember { mutableIntStateOf(0) }
    val tabs = listOf("字母表", "音标", "语法")

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Background)
    ) {
        // Header
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(Surface)
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "基础参考",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold
            )
        }

        // Tabs
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
        ) {
            tabs.forEachIndexed { index, label ->
                val isSelected = index == selectedTab
                val bg = if (isSelected) Accent else SurfaceWarm
                val textColor = if (isSelected) AccentOn else Foreground

                Text(
                    text = label,
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
                    color = textColor,
                    modifier = Modifier
                        .padding(end = 12.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(bg)
                        .padding(horizontal = 16.dp, vertical = 8.dp)
                )
            }
        }

        Spacer(modifier = Modifier.height(8.dp))

        // Content
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
        ) {
            when (selectedTab) {
                0 -> AlphabetContent()
                1 -> PhonicsContent()
                2 -> GrammarContent()
            }
        }
    }
}

@Composable
private fun AlphabetContent() {
    alphabetData.forEach { item ->
        ReferenceItem(
            char = item.char,
            phone = item.phone,
            example = item.example,
            cn = item.cn
        )
    }
}

@Composable
private fun ReferenceItem(
    char: String,
    phone: String,
    example: String,
    cn: String
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 3.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(Surface)
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = char,
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.width(40.dp)
        )
        Text(
            text = phone,
            style = MaterialTheme.typography.bodySmall,
            fontFamily = FontFamily.Monospace,
            color = Meta,
            modifier = Modifier.width(50.dp)
        )
        Text(
            text = example,
            style = MaterialTheme.typography.bodySmall,
            color = ForegroundSecondary,
            modifier = Modifier.weight(1f)
        )
        Text(
            text = cn,
            style = MaterialTheme.typography.labelSmall,
            color = Muted
        )
    }
}

@Composable
private fun PhonicsContent() {
    Text(
        text = "元音 (20个)",
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.SemiBold,
        modifier = Modifier.padding(vertical = 8.dp)
    )

    phonicsVowels.forEach { item ->
        PhonicsItem(item = item)
    }

    Spacer(modifier = Modifier.height(8.dp))

    Text(
        text = "辅音 (28个)",
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.SemiBold,
        modifier = Modifier.padding(vertical = 8.dp)
    )

    phonicsConsonants.forEach { item ->
        PhonicsItem(item = item)
    }
}

@Composable
private fun PhonicsItem(item: PhonicsItem) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 3.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(Surface)
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = item.phone,
            style = MaterialTheme.typography.bodySmall,
            fontFamily = FontFamily.Monospace,
            color = Meta,
            modifier = Modifier.width(50.dp)
        )
        Text(
            text = item.example,
            style = MaterialTheme.typography.bodySmall,
            color = Foreground
        )
        Text(
            text = item.full,
            style = MaterialTheme.typography.labelSmall,
            fontFamily = FontFamily.Monospace,
            color = Muted,
            modifier = Modifier.padding(start = 6.dp)
        )
    }
}

@Composable
private fun GrammarContent() {
    grammarData.forEach { item ->
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 4.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(Surface)
                .padding(14.dp)
        ) {
            Text(
                text = item.name,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
                color = Accent
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = item.explanation,
                style = MaterialTheme.typography.bodySmall,
                color = Muted
            )
            Text(
                text = item.chineseExplanation,
                style = MaterialTheme.typography.bodySmall,
                color = ForegroundSecondary
            )
            item.examples.forEach { (en, zh) ->
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 4.dp)
                        .clip(RoundedCornerShape(4.dp))
                        .background(Background)
                        .padding(8.dp)
                ) {
                    Text(
                        text = en,
                        style = MaterialTheme.typography.bodySmall,
                        color = Foreground
                    )
                    Text(
                        text = zh,
                        style = MaterialTheme.typography.labelSmall,
                        color = Muted
                    )
                }
            }
        }
    }
}

// ─── Data ───

private val alphabetData = listOf(
    AlphabetItem("A a", "/eɪ/", "Apple", "苹果"),
    AlphabetItem("B b", "/biː/", "Ball", "球"),
    AlphabetItem("C c", "/siː/", "Cat", "猫"),
    AlphabetItem("D d", "/diː/", "Dog", "狗"),
    AlphabetItem("E e", "/iː/", "Egg", "鸡蛋"),
    AlphabetItem("F f", "/ef/", "Fish", "鱼"),
    AlphabetItem("G g", "/dʒiː/", "Girl", "女孩"),
    AlphabetItem("H h", "/eɪtʃ/", "Hat", "帽子"),
    AlphabetItem("I i", "/aɪ/", "Ice", "冰"),
    AlphabetItem("J j", "/dʒeɪ/", "Juice", "果汁"),
    AlphabetItem("K k", "/keɪ/", "Key", "钥匙"),
    AlphabetItem("L l", "/el/", "Lion", "狮子"),
    AlphabetItem("M m", "/em/", "Moon", "月亮"),
    AlphabetItem("N n", "/en/", "Nest", "巢"),
    AlphabetItem("O o", "/əʊ/", "Orange", "橙子"),
    AlphabetItem("P p", "/piː/", "Pen", "钢笔"),
    AlphabetItem("Q q", "/kjuː/", "Queen", "女王"),
    AlphabetItem("R r", "/ɑːr/", "Rain", "雨"),
    AlphabetItem("S s", "/es/", "Sun", "太阳"),
    AlphabetItem("T t", "/tiː/", "Tree", "树"),
    AlphabetItem("U u", "/juː/", "Umbrella", "雨伞"),
    AlphabetItem("V v", "/viː/", "Violin", "小提琴"),
    AlphabetItem("W w", "/ˈdʌbljuː/", "Water", "水"),
    AlphabetItem("X x", "/eks/", "X-ray", "X光"),
    AlphabetItem("Y y", "/waɪ/", "Yellow", "黄色"),
    AlphabetItem("Z z", "/zed/", "Zebra", "斑马")
)

private val phonicsVowels = listOf(
    PhonicsItem("/iː/", "see", "/siː/"),
    PhonicsItem("/ɪ/", "sit", "/sɪt/"),
    PhonicsItem("/e/", "bed", "/bed/"),
    PhonicsItem("/æ/", "cat", "/kæt/"),
    PhonicsItem("/ɑː/", "car", "/kɑːr/"),
    PhonicsItem("/ɒ/", "hot", "/hɒt/"),
    PhonicsItem("/ɔː/", "door", "/dɔːr/"),
    PhonicsItem("/ʊ/", "book", "/bʊk/"),
    PhonicsItem("/uː/", "moon", "/muːn/"),
    PhonicsItem("/ʌ/", "cup", "/kʌp/"),
    PhonicsItem("/ɜː/", "bird", "/bɜːd/"),
    PhonicsItem("/ə/", "about", "/əˈbaʊt/"),
    PhonicsItem("/eɪ/", "cake", "/keɪk/"),
    PhonicsItem("/aɪ/", "time", "/taɪm/"),
    PhonicsItem("/ɔɪ/", "boy", "/bɔɪ/"),
    PhonicsItem("/aʊ/", "house", "/haʊs/"),
    PhonicsItem("/əʊ/", "home", "/həʊm/"),
    PhonicsItem("/ɪə/", "ear", "/ɪər/"),
    PhonicsItem("/eə/", "hair", "/heər/"),
    PhonicsItem("/ʊə/", "tour", "/tʊər/")
)

private val phonicsConsonants = listOf(
    PhonicsItem("/p/", "pen", "/pen/"),
    PhonicsItem("/b/", "book", "/bʊk/"),
    PhonicsItem("/t/", "top", "/tɒp/"),
    PhonicsItem("/d/", "dog", "/dɒɡ/"),
    PhonicsItem("/k/", "cat", "/kæt/"),
    PhonicsItem("/ɡ/", "go", "/ɡəʊ/"),
    PhonicsItem("/f/", "fish", "/fɪʃ/"),
    PhonicsItem("/v/", "van", "/væn/"),
    PhonicsItem("/θ/", "think", "/θɪŋk/"),
    PhonicsItem("/ð/", "this", "/ðɪs/"),
    PhonicsItem("/s/", "sun", "/sʌn/"),
    PhonicsItem("/z/", "zoo", "/zuː/"),
    PhonicsItem("/ʃ/", "ship", "/ʃɪp/"),
    PhonicsItem("/ʒ/", "vision", "/ˈvɪʒən/"),
    PhonicsItem("/h/", "hat", "/hæt/"),
    PhonicsItem("/m/", "man", "/mæn/"),
    PhonicsItem("/n/", "nose", "/nəʊz/"),
    PhonicsItem("/ŋ/", "sing", "/sɪŋ/"),
    PhonicsItem("/l/", "leg", "/leɡ/"),
    PhonicsItem("/r/", "red", "/red/"),
    PhonicsItem("/j/", "yes", "/jes/"),
    PhonicsItem("/w/", "wet", "/wet/"),
    PhonicsItem("/tʃ/", "chips", "/tʃɪps/"),
    PhonicsItem("/dʒ/", "jump", "/dʒʌmp/"),
    PhonicsItem("/tr/", "tree", "/triː/"),
    PhonicsItem("/dr/", "dress", "/dres/"),
    PhonicsItem("/ts/", "cats", "/kæts/"),
    PhonicsItem("/dz/", "beds", "/bedz/")
)

private val grammarData = listOf(
    GrammarItem(
        "名词复数 (Plural Nouns)",
        "book → books, box → boxes, baby → babies",
        "一般情况下加 -s；以 s/x/ch/sh 结尾加 -es；辅音+y 变 y 为 i 加 -es。",
        listOf("I have two books." to "我有两本书。", "She packed three boxes." to "她打包了三个箱子。")
    ),
    GrammarItem(
        "一般过去式 (Past Tense)",
        "walk → walked, go → went",
        "规则动词加 -ed；不规则动词需单独记忆。常用于描述已发生的事。",
        listOf("He walked to school yesterday." to "他昨天走路去学校。", "She went to the park last Sunday." to "她上周日去了公园。")
    ),
    GrammarItem(
        "现在进行时 (Present Continuous)",
        "is/am/are + doing",
        "表示此刻正在进行的动作或现阶段持续的状态。",
        listOf("She is reading a book right now." to "她正在看书。", "They are learning English this year." to "他们今年在学习英语。")
    ),
    GrammarItem(
        "过去进行时 (Past Continuous)",
        "was/were + doing",
        "表示过去某一时刻正在进行的动作。",
        listOf("I was watching TV when she called." to "她打电话时我正在看电视。", "They were playing football at 3pm." to "下午三点他们正在踢足球。")
    ),
    GrammarItem(
        "一般将来时 (Future Tense)",
        "will + do / be going to",
        "will 表示主观意愿或临时决定；be going to 表示已有计划或客观迹象。",
        listOf("I will call you tomorrow." to "我明天会给你打电话。", "It is going to rain soon." to "快要下雨了。")
    ),
    GrammarItem(
        "现在完成时 (Present Perfect)",
        "have/has + done",
        "表示过去发生的动作对现在有影响，或持续到现在的经历。",
        listOf("I have finished my homework." to "我做完作业了。", "She has lived here for five years." to "她在这里住了五年。")
    ),
    GrammarItem(
        "比较级与最高级 (Comparative & Superlative)",
        "big → bigger → biggest",
        "单音节词加 -er/-est；多音节词加 more/most。用于比较事物之间的程度。",
        listOf("This book is bigger than that one." to "这本书比那本大。", "She is the tallest in her class." to "她是班里最高的。")
    ),
    GrammarItem(
        "冠词 (Articles)",
        "a / an / the",
        "a/an 用于泛指（不定冠词）；the 用于特指（定冠词）。a 用于辅音音素前，an 用于元音音素前。",
        listOf("I saw a cat. The cat was black." to "我看见一只猫。那只猫是黑色的。", "She is an engineer." to "她是一名工程师。")
    ),
    GrammarItem(
        "基础介词 (Prepositions)",
        "in / on / at",
        "in 表示在较大空间/时间内；on 表示在表面/某一天；at 表示在具体点/时刻。",
        listOf("The book is on the table." to "书在桌子上。", "I will meet you at 3pm in the park." to "我下午三点在公园见你。")
    ),
    GrammarItem(
        "基础情态动词 (Modal Verbs)",
        "can / must / should",
        "can 表示能力或许可；must 表示必须；should 表示建议。情态动词后接动词原形。",
        listOf("I can swim." to "我会游泳。", "You must wear a seatbelt." to "你必须系安全带。", "You should drink more water." to "你应该多喝水。")
    )
)
