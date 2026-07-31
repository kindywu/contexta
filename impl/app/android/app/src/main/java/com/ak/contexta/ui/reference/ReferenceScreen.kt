package com.ak.contexta.ui.reference

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.ak.contexta.ui.components.AppButton
import com.ak.contexta.ui.components.AppIconButton
import com.ak.contexta.ui.components.AppModal
import com.ak.contexta.ui.components.AppTopBar
import com.ak.contexta.ui.theme.Background
import com.ak.contexta.ui.theme.BodyText
import com.ak.contexta.ui.theme.Ink
import com.ak.contexta.ui.theme.Muted
import com.ak.contexta.ui.theme.MutedSoft
import com.ak.contexta.ui.theme.PhoneticStyle
import com.ak.contexta.ui.theme.Primary
import com.ak.contexta.ui.theme.SurfaceCard

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

/** 弹窗展示数据：字母或音标格子点击后弹出 */
data class ReferenceCellData(
    val char: String,        // 字母 "A a" 或音标 "/iː/"
    val reading: String,     // 字母 → 音标；音标 → 分类名
    val example: String,     // 例词
    val exampleCn: String,   // 例词中文
    val isPhonetic: Boolean  // false=字母格子, true=音标格子（弹窗头部区分类别展示）
)

@Composable
fun ReferenceScreen(
    viewModel: ReferenceViewModel = hiltViewModel()
) {
    var selectedTab by remember { mutableIntStateOf(0) }
    val tabs = listOf("字母表", "音标", "语法")
    val onSpeak: (String) -> Unit = { text -> viewModel.speak(text) }
    var selectedCell by remember { mutableStateOf<ReferenceCellData?>(null) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Background)
    ) {
        // Header
        AppTopBar(title = "基础参考")

        // Tabs (inline underline style)
        Row(modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp)) {
            tabs.forEachIndexed { index, label ->
                val isSelected = index == selectedTab
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .clickable { selectedTab = index }
                        .padding(end = 24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(
                        text = label,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = if (isSelected) FontWeight.Medium else FontWeight.Normal,
                        color = if (isSelected) Primary else MutedSoft
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(2.dp)
                            .background(if (isSelected) Primary else androidx.compose.ui.graphics.Color.Transparent)
                    )
                }
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
                0 -> AlphabetContent(onCellClick = { selectedCell = it })
                1 -> PhonicsContent(onCellClick = { selectedCell = it })
                2 -> GrammarContent(onSpeak = onSpeak)
            }
        }
    }

    AppModal(visible = selectedCell != null, onDismiss = { selectedCell = null }) {
        selectedCell?.let { cell ->
            Box(modifier = Modifier.fillMaxWidth()) {
                AppIconButton(
                    icon = Icons.Outlined.Close,
                    contentDescription = "关闭",
                    onClick = { selectedCell = null },
                    modifier = Modifier.align(Alignment.TopEnd),
                    size = 32,
                    tint = MutedSoft
                )
            }
            // 56sp serif character
            Text(
                text = cell.char,
                style = MaterialTheme.typography.displayLarge.copy(fontSize = 56.sp),
                modifier = Modifier.align(Alignment.CenterHorizontally)
            )
            Spacer(modifier = Modifier.height(8.dp))
            // reading: phonetic in coral (letters) / category name (phonetics)
            if (cell.isPhonetic) {
                Text(
                    text = cell.reading,
                    style = MaterialTheme.typography.bodyMedium,
                    color = Muted,
                    modifier = Modifier.align(Alignment.CenterHorizontally)
                )
            } else {
                Text(
                    text = cell.reading,
                    style = PhoneticStyle.copy(fontSize = 15.sp),
                    modifier = Modifier.align(Alignment.CenterHorizontally)
                )
            }
            Spacer(modifier = Modifier.height(12.dp))
            // Example
            Text(
                text = cell.example + if (cell.exampleCn.isNotEmpty()) "  ${cell.exampleCn}" else "",
                style = MaterialTheme.typography.bodyMedium,
                color = BodyText,
                modifier = Modifier.align(Alignment.CenterHorizontally)
            )
            Spacer(modifier = Modifier.height(20.dp))
            // Speak button
            AppButton(
                text = "发音",
                onClick = { viewModel.speak(cell.example) },
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(modifier = Modifier.height(4.dp))
        }
    }
}

@Composable
private fun AlphabetContent(onCellClick: (ReferenceCellData) -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 16.dp)
    ) {
        alphabetData.chunked(4).forEach { row ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                row.forEach { item ->
                    AlphabetGridCard(
                        item = item,
                        onClick = { onCellClick(ReferenceCellData(item.char, item.phone, item.example, item.cn, isPhonetic = false)) },
                        modifier = Modifier.weight(1f)
                    )
                }
                // 补齐最后一行空白格，保持对齐
                repeat(4 - row.size) {
                    Spacer(modifier = Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun AlphabetGridCard(
    item: AlphabetItem,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(8.dp))
            .background(SurfaceCard)
            .clickable(onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = item.char,
            style = MaterialTheme.typography.titleMedium,
            color = Ink
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = item.phone,
            style = PhoneticStyle.copy(fontSize = 13.sp)
        )
    }
}

@Composable
private fun SectionHeader(title: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .width(3.dp)
                .height(16.dp)
                .background(Primary, RoundedCornerShape(2.dp))
        )
        Spacer(modifier = Modifier.width(8.dp))
        Text(
            text = title,
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
            color = Primary
        )
    }
}

@Composable
private fun PhonicsContent(onCellClick: (ReferenceCellData) -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 16.dp)
    ) {
        phonicsGroups.forEach { group ->
            SectionHeader(title = group.name)
            group.items.chunked(3).forEach { row ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(bottom = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    row.forEach { item ->
                        PhonicsGridCard(
                            item = item,
                            onClick = { onCellClick(ReferenceCellData(item.phone, group.name, item.example, "", isPhonetic = true)) },
                            modifier = Modifier.weight(1f)
                        )
                    }
                    repeat(3 - row.size) {
                        Spacer(modifier = Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

@Composable
private fun PhonicsGridCard(
    item: PhonicsItem,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(8.dp))
            .background(SurfaceCard)
            .clickable(onClick = onClick)
            .padding(horizontal = 8.dp, vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = item.phone,
            style = PhoneticStyle.copy(fontSize = 15.sp)
        )
        Spacer(modifier = Modifier.height(2.dp))
        Text(
            text = item.example,
            style = MaterialTheme.typography.bodyMedium,
            color = BodyText
        )
        Spacer(modifier = Modifier.height(1.dp))
        Text(
            text = item.full,
            style = MaterialTheme.typography.labelSmall,
            color = Muted
        )
    }
}

@Composable
private fun GrammarContent(onSpeak: (String) -> Unit) {
    grammarGroups.flatMap { it.items }.forEach { item ->
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 4.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(SurfaceCard)
                .padding(14.dp)
        ) {
            Text(
                text = item.name,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
                color = Primary
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
                color = BodyText
            )
            item.examples.forEach { (en, zh) ->
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 4.dp)
                        .clip(RoundedCornerShape(4.dp))
                        .background(Background)
                        .clickable { onSpeak(en) }
                        .padding(8.dp)
                ) {
                    Text(
                        text = en,
                        style = MaterialTheme.typography.bodySmall,
                        color = Ink
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

data class PhonicsGroup(val name: String, val items: List<PhonicsItem>)

private val phonicsGroups = listOf(
    PhonicsGroup("单元音 (12)", listOf(
        PhonicsItem("/iː/", "see", "/siː/"), PhonicsItem("/ɪ/", "sit", "/sɪt/"),
        PhonicsItem("/e/", "bed", "/bed/"), PhonicsItem("/æ/", "cat", "/kæt/"),
        PhonicsItem("/ɑː/", "car", "/kɑːr/"), PhonicsItem("/ɒ/", "hot", "/hɒt/"),
        PhonicsItem("/ɔː/", "door", "/dɔːr/"), PhonicsItem("/ʊ/", "book", "/bʊk/"),
        PhonicsItem("/uː/", "moon", "/muːn/"), PhonicsItem("/ʌ/", "cup", "/kʌp/"),
        PhonicsItem("/ɜː/", "bird", "/bɜːd/"), PhonicsItem("/ə/", "about", "/əˈbaʊt/")
    )),
    PhonicsGroup("双元音 (8)", listOf(
        PhonicsItem("/eɪ/", "cake", "/keɪk/"), PhonicsItem("/aɪ/", "time", "/taɪm/"),
        PhonicsItem("/ɔɪ/", "boy", "/bɔɪ/"), PhonicsItem("/aʊ/", "house", "/haʊs/"),
        PhonicsItem("/əʊ/", "home", "/həʊm/"), PhonicsItem("/ɪə/", "ear", "/ɪər/"),
        PhonicsItem("/eə/", "hair", "/heər/"), PhonicsItem("/ʊə/", "tour", "/tʊər/")
    )),
    PhonicsGroup("爆破音 (6)", listOf(
        PhonicsItem("/p/", "pen", "/pen/"), PhonicsItem("/b/", "book", "/bʊk/"),
        PhonicsItem("/t/", "top", "/tɒp/"), PhonicsItem("/d/", "dog", "/dɒɡ/"),
        PhonicsItem("/k/", "cat", "/kæt/"), PhonicsItem("/ɡ/", "go", "/ɡəʊ/")
    )),
    PhonicsGroup("摩擦音 (10)", listOf(
        PhonicsItem("/f/", "fish", "/fɪʃ/"), PhonicsItem("/v/", "van", "/væn/"),
        PhonicsItem("/θ/", "think", "/θɪŋk/"), PhonicsItem("/ð/", "this", "/ðɪs/"),
        PhonicsItem("/s/", "sun", "/sʌn/"), PhonicsItem("/z/", "zoo", "/zuː/"),
        PhonicsItem("/ʃ/", "ship", "/ʃɪp/"), PhonicsItem("/ʒ/", "vision", "/ˈvɪʒən/"),
        PhonicsItem("/h/", "hat", "/hæt/"), PhonicsItem("/r/", "red", "/red/")
    )),
    PhonicsGroup("破擦音 (6)", listOf(
        PhonicsItem("/tʃ/", "chips", "/tʃɪps/"), PhonicsItem("/dʒ/", "jump", "/dʒʌmp/"),
        PhonicsItem("/tr/", "tree", "/triː/"), PhonicsItem("/dr/", "dress", "/dres/"),
        PhonicsItem("/ts/", "cats", "/kæts/"), PhonicsItem("/dz/", "beds", "/bedz/")
    )),
    PhonicsGroup("鼻辅音 (3)", listOf(
        PhonicsItem("/m/", "man", "/mæn/"), PhonicsItem("/n/", "nose", "/nəʊz/"),
        PhonicsItem("/ŋ/", "sing", "/sɪŋ/")
    )),
    PhonicsGroup("舌侧音 (1)", listOf(
        PhonicsItem("/l/", "leg", "/leɡ/")
    )),
    PhonicsGroup("半元音 (2)", listOf(
        PhonicsItem("/j/", "yes", "/jes/"), PhonicsItem("/w/", "wet", "/wet/")
    ))
)
