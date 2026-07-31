package com.ak.contexta.ui.reference

data class GrammarItem(
    val name: String,
    val explanation: String,
    val chineseExplanation: String,
    val examples: List<Pair<String, String>>
)

data class GrammarGroup(
    val name: String,
    val items: List<GrammarItem>
)

val grammarGroups = listOf(
    GrammarGroup("时态", listOf(
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
        )
    )),
    GrammarGroup("词形变化", listOf(
        GrammarItem(
            "名词复数 (Plural Nouns)",
            "book → books, box → boxes, baby → babies",
            "一般情况下加 -s；以 s/x/ch/sh 结尾加 -es；辅音+y 变 y 为 i 加 -es。",
            listOf("I have two books." to "我有两本书。", "She packed three boxes." to "她打包了三个箱子。")
        ),
        GrammarItem(
            "比较级与最高级 (Comparative & Superlative)",
            "big → bigger → biggest",
            "单音节词加 -er/-est；多音节词加 more/most。用于比较事物之间的程度。",
            listOf("This book is bigger than that one." to "这本书比那本大。", "She is the tallest in her class." to "她是班里最高的。")
        )
    )),
    GrammarGroup("功能词", listOf(
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
    ))
)
