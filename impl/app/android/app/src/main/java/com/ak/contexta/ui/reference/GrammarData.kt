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
            "一般现在时 (Present Simple)",
            "I work / She works",
            "表示习惯性动作、客观事实或常态；主语为第三人称单数（he/she/it）时动词加 -s/-es。",
            listOf("I get up at seven every day." to "我每天七点起床。", "The sun rises in the east." to "太阳从东方升起。")
        ),
        GrammarItem(
            "一般过去时 (Past Tense)",
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
            "第三人称单数 (Third Person Singular)",
            "walk → walks, go → goes, watch → watches",
            "一般现在时主语为 he/she/it 时动词加 -s；以 s/x/ch/sh/o 结尾加 -es；辅音+y 变 y 为 i 加 -es。",
            listOf("She watches TV every evening." to "她每天晚上看电视。", "He goes to school by bus." to "他坐公交上学。")
        ),
        GrammarItem(
            "动词 -ing 形式 (-ing Form)",
            "run → running, make → making, read → reading",
            "一般直接加 -ing；以不发音 e 结尾去 e 加 -ing；重读闭音节双写末尾辅音加 -ing。用于进行时等。",
            listOf("She is running in the park." to "她正在公园跑步。", "I am making dinner now." to "我正在做晚饭。")
        ),
        GrammarItem(
            "不规则动词 (Irregular Verbs)",
            "go → went → gone, eat → ate → eaten, see → saw → seen",
            "过去式和过去分词不按规则变化，需单独记忆；常用于完成时。",
            listOf("I ate breakfast at seven." to "我七点吃了早饭。", "She has seen this movie before." to "她以前看过这部电影。")
        ),
        GrammarItem(
            "比较级与最高级 (Comparative & Superlative)",
            "big → bigger → biggest",
            "单音节词加 -er/-est；多音节词加 more/most。用于比较事物之间的程度。",
            listOf("This book is bigger than that one." to "这本书比那本大。", "She is the tallest in her class." to "她是班里最高的。")
        ),
        GrammarItem(
            "名词所有格 (Possessive)",
            "'s / s' / of",
            "有生命名词用 's（复数以 s 结尾只加 '）；无生命名词常用 of 结构。表示所属关系。",
            listOf("This is Tom's bike." to "这是汤姆的自行车。", "The door of the room is open." to "房间的门开着。")
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
        ),
        GrammarItem(
            "连词 (Conjunctions)",
            "and / but / or / because / so",
            "and 表并列；but 表转折；or 表选择；because 表原因；so 表结果。用于连接词、短语或句子。",
            listOf("I like tea and coffee." to "我喜欢茶和咖啡。", "He was tired, so he went to bed early." to "他累了，所以早早睡了。")
        ),
        GrammarItem(
            "疑问词 (Question Words)",
            "what / who / when / where / why / how",
            "what 问事物；who 问人；when 问时间；where 问地点；why 问原因；how 问方式。用于特殊疑问句。",
            listOf("Where do you live?" to "你住在哪里？", "Why are you late?" to "你为什么迟到？")
        )
    )),
    GrammarGroup("句式", listOf(
        GrammarItem(
            "There be 句型 (There be)",
            "There is/are + 名词 + 地点",
            "表示\"某处有某物\"；单数用 is，复数用 are；遵循就近原则。",
            listOf("There is a book on the desk." to "书桌上有一本书。", "There are two cats under the table." to "桌子底下有两只猫。")
        ),
        GrammarItem(
            "一般疑问句 (Yes/No Questions)",
            "Are you…? / Do you…? / Did you…?",
            "be 动词或助动词提到句首构成疑问；回答用 Yes/No。",
            listOf("Are you a student?" to "你是学生吗？", "Did you finish your homework?" to "你做完作业了吗？")
        ),
        GrammarItem(
            "否定句 (Negation)",
            "am not / isn't / aren't / don't / doesn't / didn't",
            "be 动词后加 not；行为动词借助 don't/doesn't/didn't 构成否定。",
            listOf("I am not tired." to "我不累。", "She doesn't like coffee." to "她不喜欢咖啡。")
        ),
        GrammarItem(
            "祈使句 (Imperatives)",
            "Open the door. / Don't be late.",
            "动词原形开头表示请求、命令或建议；否定用 Don't + 动词原形。",
            listOf("Please sit down." to "请坐。", "Don't forget your keys." to "别忘了你的钥匙。")
        ),
        GrammarItem(
            "感叹句 (Exclamations)",
            "What a …! / How …!",
            "What + 名词短语表感叹；How + 形容词/副词表感叹。",
            listOf("What a nice day!" to "多好的天气啊！", "How beautiful the flowers are!" to "这些花多漂亮啊！")
        ),
        GrammarItem(
            "基本语序 (Word Order)",
            "主语 + 谓语 + 宾语 + 地点 + 时间",
            "英语基本语序为主谓宾；时间地点状语通常置于句末，地点在前、时间在后。",
            listOf("I met my friend at the park yesterday." to "我昨天在公园遇到了我的朋友。", "She reads English in the morning." to "她早上读英语。")
        )
    ))
)
