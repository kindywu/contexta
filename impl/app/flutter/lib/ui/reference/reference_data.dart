/// Reference 页静态数据（对照 Kotlin ui/reference/GrammarData.kt 与
/// ReferenceScreen.kt 的 Data 段）。
///
/// 音标映射 / speak 文本规则与 Kotlin 完全一致，纯函数供单元测试覆盖。
library;

/// 弹窗展示数据：字母或音标格子点击后弹出（对照 Kotlin ReferenceCellData）。
class ReferenceCellData {
  const ReferenceCellData({
    required this.char,
    required this.reading,
    required this.example,
    required this.exampleCn,
    required this.isPhonetic,
  });

  final String char; // 字母 "A a" 或音标 "/iː/"
  final String reading; // 字母 → 音标；音标 → 分类名
  final String example; // 例词
  final String exampleCn; // 例词中文
  final bool isPhonetic; // false=字母格子, true=音标格子
}

/// 语法条目。
class GrammarItem {
  const GrammarItem({
    required this.name,
    required this.explanation,
    required this.chineseExplanation,
    required this.examples,
  });

  final String name;
  final String explanation;
  final String chineseExplanation;
  final List<(String, String)> examples;
}

/// 语法分组。
class GrammarGroup {
  const GrammarGroup({required this.name, required this.items});

  final String name;
  final List<GrammarItem> items;
}

/// 语法内容（4 组 23 条，对照 Kotlin grammarGroups）。
const List<GrammarGroup> grammarGroups = [
  GrammarGroup(name: '时态', items: [
    GrammarItem(
      name: '一般现在时 (Present Simple)',
      explanation: 'I work / She works',
      chineseExplanation: '表示习惯性动作、客观事实或常态；主语为第三人称单数（he/she/it）时动词加 -s/-es。',
      examples: [
        ('I get up at seven every day.', '我每天七点起床。'),
        ('The sun rises in the east.', '太阳从东方升起。'),
      ],
    ),
    GrammarItem(
      name: '一般过去时 (Past Tense)',
      explanation: 'walk → walked, go → went',
      chineseExplanation: '规则动词加 -ed；不规则动词需单独记忆。常用于描述已发生的事。',
      examples: [
        ('He walked to school yesterday.', '他昨天走路去学校。'),
        ('She went to the park last Sunday.', '她上周日去了公园。'),
      ],
    ),
    GrammarItem(
      name: '现在进行时 (Present Continuous)',
      explanation: 'is/am/are + doing',
      chineseExplanation: '表示此刻正在进行的动作或现阶段持续的状态。',
      examples: [
        ('She is reading a book right now.', '她正在看书。'),
        ('They are learning English this year.', '他们今年在学习英语。'),
      ],
    ),
    GrammarItem(
      name: '过去进行时 (Past Continuous)',
      explanation: 'was/were + doing',
      chineseExplanation: '表示过去某一时刻正在进行的动作。',
      examples: [
        ('I was watching TV when she called.', '她打电话时我正在看电视。'),
        ('They were playing football at 3pm.', '下午三点他们正在踢足球。'),
      ],
    ),
    GrammarItem(
      name: '一般将来时 (Future Tense)',
      explanation: 'will + do / be going to',
      chineseExplanation: 'will 表示主观意愿或临时决定；be going to 表示已有计划或客观迹象。',
      examples: [
        ('I will call you tomorrow.', '我明天会给你打电话。'),
        ('It is going to rain soon.', '快要下雨了。'),
      ],
    ),
    GrammarItem(
      name: '现在完成时 (Present Perfect)',
      explanation: 'have/has + done',
      chineseExplanation: '表示过去发生的动作对现在有影响，或持续到现在的经历。',
      examples: [
        ('I have finished my homework.', '我做完作业了。'),
        ('She has lived here for five years.', '她在这里住了五年。'),
      ],
    ),
  ]),
  GrammarGroup(name: '词形变化', items: [
    GrammarItem(
      name: '名词复数 (Plural Nouns)',
      explanation: 'book → books, box → boxes, baby → babies',
      chineseExplanation: '一般情况下加 -s；以 s/x/ch/sh 结尾加 -es；辅音+y 变 y 为 i 加 -es。',
      examples: [
        ('I have two books.', '我有两本书。'),
        ('She packed three boxes.', '她打包了三个箱子。'),
      ],
    ),
    GrammarItem(
      name: '第三人称单数 (Third Person Singular)',
      explanation: 'walk → walks, go → goes, watch → watches',
      chineseExplanation: '一般现在时主语为 he/she/it 时动词加 -s；以 s/x/ch/sh/o 结尾加 -es；辅音+y 变 y 为 i 加 -es。',
      examples: [
        ('She watches TV every evening.', '她每天晚上看电视。'),
        ('He goes to school by bus.', '他坐公交上学。'),
      ],
    ),
    GrammarItem(
      name: '动词 -ing 形式 (-ing Form)',
      explanation: 'run → running, make → making, read → reading',
      chineseExplanation: '一般直接加 -ing；以不发音 e 结尾去 e 加 -ing；重读闭音节双写末尾辅音加 -ing。用于进行时等。',
      examples: [
        ('She is running in the park.', '她正在公园跑步。'),
        ('I am making dinner now.', '我正在做晚饭。'),
      ],
    ),
    GrammarItem(
      name: '不规则动词 (Irregular Verbs)',
      explanation: 'go → went → gone, eat → ate → eaten, see → saw → seen',
      chineseExplanation: '过去式和过去分词不按规则变化，需单独记忆；常用于完成时。',
      examples: [
        ('I ate breakfast at seven.', '我七点吃了早饭。'),
        ('She has seen this movie before.', '她以前看过这部电影。'),
      ],
    ),
    GrammarItem(
      name: '比较级与最高级 (Comparative & Superlative)',
      explanation: 'big → bigger → biggest',
      chineseExplanation: '单音节词加 -er/-est；多音节词加 more/most。用于比较事物之间的程度。',
      examples: [
        ('This book is bigger than that one.', '这本书比那本大。'),
        ('She is the tallest in her class.', '她是班里最高的。'),
      ],
    ),
    GrammarItem(
      name: '名词所有格 (Possessive)',
      explanation: "'s / s' / of",
      chineseExplanation: "有生命名词用 's（复数以 s 结尾只加 '）；无生命名词常用 of 结构。表示所属关系。",
      examples: [
        ("This is Tom's bike.", '这是汤姆的自行车。'),
        ('The door of the room is open.', '房间的门开着。'),
      ],
    ),
  ]),
  GrammarGroup(name: '功能词', items: [
    GrammarItem(
      name: '冠词 (Articles)',
      explanation: 'a / an / the',
      chineseExplanation: 'a/an 用于泛指（不定冠词）；the 用于特指（定冠词）。a 用于辅音音素前，an 用于元音音素前。',
      examples: [
        ('I saw a cat. The cat was black.', '我看见一只猫。那只猫是黑色的。'),
        ('She is an engineer.', '她是一名工程师。'),
      ],
    ),
    GrammarItem(
      name: '基础介词 (Prepositions)',
      explanation: 'in / on / at',
      chineseExplanation: 'in 表示在较大空间/时间内；on 表示在表面/某一天；at 表示在具体点/时刻。',
      examples: [
        ('The book is on the table.', '书在桌子上。'),
        ('I will meet you at 3pm in the park.', '我下午三点在公园见你。'),
      ],
    ),
    GrammarItem(
      name: '基础情态动词 (Modal Verbs)',
      explanation: 'can / must / should',
      chineseExplanation: 'can 表示能力或许可；must 表示必须；should 表示建议。情态动词后接动词原形。',
      examples: [
        ('I can swim.', '我会游泳。'),
        ('You must wear a seatbelt.', '你必须系安全带。'),
        ('You should drink more water.', '你应该多喝水。'),
      ],
    ),
    GrammarItem(
      name: '连词 (Conjunctions)',
      explanation: 'and / but / or / because / so',
      chineseExplanation: 'and 表并列；but 表转折；or 表选择；because 表原因；so 表结果。用于连接词、短语或句子。',
      examples: [
        ('I like tea and coffee.', '我喜欢茶和咖啡。'),
        ('He was tired, so he went to bed early.', '他累了，所以早早睡了。'),
      ],
    ),
    GrammarItem(
      name: '疑问词 (Question Words)',
      explanation: 'what / who / when / where / why / how',
      chineseExplanation: 'what 问事物；who 问人；when 问时间；where 问地点；why 问原因；how 问方式。用于特殊疑问句。',
      examples: [
        ('Where do you live?', '你住在哪里？'),
        ('Why are you late?', '你为什么迟到？'),
      ],
    ),
  ]),
  GrammarGroup(name: '句式', items: [
    GrammarItem(
      name: 'There be 句型 (There be)',
      explanation: 'There is/are + 名词 + 地点',
      chineseExplanation: '表示"某处有某物"；单数用 is，复数用 are；遵循就近原则。',
      examples: [
        ('There is a book on the desk.', '书桌上有一本书。'),
        ('There are two cats under the table.', '桌子底下有两只猫。'),
      ],
    ),
    GrammarItem(
      name: '一般疑问句 (Yes/No Questions)',
      explanation: 'Are you…? / Do you…? / Did you…?',
      chineseExplanation: 'be 动词或助动词提到句首构成疑问；回答用 Yes/No。',
      examples: [
        ('Are you a student?', '你是学生吗？'),
        ('Did you finish your homework?', '你做完作业了吗？'),
      ],
    ),
    GrammarItem(
      name: '否定句 (Negation)',
      explanation: "am not / isn't / aren't / don't / doesn't / didn't",
      chineseExplanation: "be 动词后加 not；行为动词借助 don't/doesn't/didn't 构成否定。",
      examples: [
        ('I am not tired.', '我不累。'),
        ("She doesn't like coffee.", '她不喜欢咖啡。'),
      ],
    ),
    GrammarItem(
      name: '祈使句 (Imperatives)',
      explanation: "Open the door. / Don't be late.",
      chineseExplanation: "动词原形开头表示请求、命令或建议；否定用 Don't + 动词原形。",
      examples: [
        ('Please sit down.', '请坐。'),
        ("Don't forget your keys.", '别忘了你的钥匙。'),
      ],
    ),
    GrammarItem(
      name: '感叹句 (Exclamations)',
      explanation: 'What a …! / How …!',
      chineseExplanation: 'What + 名词短语表感叹；How + 形容词/副词表感叹。',
      examples: [
        ('What a nice day!', '多好的天气啊！'),
        ('How beautiful the flowers are!', '这些花多漂亮啊！'),
      ],
    ),
    GrammarItem(
      name: '基本语序 (Word Order)',
      explanation: '主语 + 谓语 + 宾语 + 地点 + 时间',
      chineseExplanation: '英语基本语序为主谓宾；时间地点状语通常置于句末，地点在前、时间在后。',
      examples: [
        ('I met my friend at the park yesterday.', '我昨天在公园遇到了我的朋友。'),
        ('She reads English in the morning.', '她早上读英语。'),
      ],
    ),
  ]),
];

/// 字母表（26 个，对照 Kotlin alphabetData）。
class AlphabetItem {
  const AlphabetItem({
    required this.char,
    required this.phone,
    required this.example,
    required this.cn,
  });

  final String char;
  final String phone;
  final String example;
  final String cn;
}

const List<AlphabetItem> alphabetData = [
  AlphabetItem(char: 'A a', phone: '/eɪ/', example: 'Apple', cn: '苹果'),
  AlphabetItem(char: 'B b', phone: '/biː/', example: 'Ball', cn: '球'),
  AlphabetItem(char: 'C c', phone: '/siː/', example: 'Cat', cn: '猫'),
  AlphabetItem(char: 'D d', phone: '/diː/', example: 'Dog', cn: '狗'),
  AlphabetItem(char: 'E e', phone: '/iː/', example: 'Egg', cn: '鸡蛋'),
  AlphabetItem(char: 'F f', phone: '/ef/', example: 'Fish', cn: '鱼'),
  AlphabetItem(char: 'G g', phone: '/dʒiː/', example: 'Girl', cn: '女孩'),
  AlphabetItem(char: 'H h', phone: '/eɪtʃ/', example: 'Hat', cn: '帽子'),
  AlphabetItem(char: 'I i', phone: '/aɪ/', example: 'Ice', cn: '冰'),
  AlphabetItem(char: 'J j', phone: '/dʒeɪ/', example: 'Juice', cn: '果汁'),
  AlphabetItem(char: 'K k', phone: '/keɪ/', example: 'Key', cn: '钥匙'),
  AlphabetItem(char: 'L l', phone: '/el/', example: 'Lion', cn: '狮子'),
  AlphabetItem(char: 'M m', phone: '/em/', example: 'Moon', cn: '月亮'),
  AlphabetItem(char: 'N n', phone: '/en/', example: 'Nest', cn: '巢'),
  AlphabetItem(char: 'O o', phone: '/əʊ/', example: 'Orange', cn: '橙子'),
  AlphabetItem(char: 'P p', phone: '/piː/', example: 'Pen', cn: '钢笔'),
  AlphabetItem(char: 'Q q', phone: '/kjuː/', example: 'Queen', cn: '女王'),
  AlphabetItem(char: 'R r', phone: '/ɑːr/', example: 'Rain', cn: '雨'),
  AlphabetItem(char: 'S s', phone: '/es/', example: 'Sun', cn: '太阳'),
  AlphabetItem(char: 'T t', phone: '/tiː/', example: 'Tree', cn: '树'),
  AlphabetItem(char: 'U u', phone: '/juː/', example: 'Umbrella', cn: '雨伞'),
  AlphabetItem(char: 'V v', phone: '/viː/', example: 'Violin', cn: '小提琴'),
  AlphabetItem(char: 'W w', phone: '/ˈdʌbljuː/', example: 'Water', cn: '水'),
  AlphabetItem(char: 'X x', phone: '/eks/', example: 'X-ray', cn: 'X光'),
  AlphabetItem(char: 'Y y', phone: '/waɪ/', example: 'Yellow', cn: '黄色'),
  AlphabetItem(char: 'Z z', phone: '/zed/', example: 'Zebra', cn: '斑马'),
];

/// 音标分组（对照 Kotlin phonicsGroups）。
class PhonicsItem {
  const PhonicsItem({
    required this.phone,
    required this.example,
    required this.full,
  });

  final String phone;
  final String example;
  final String full;
}

class PhonicsGroup {
  const PhonicsGroup({required this.name, required this.items});

  final String name;
  final List<PhonicsItem> items;
}

const List<PhonicsGroup> phonicsGroups = [
  PhonicsGroup(name: '单元音 (12)', items: [
    PhonicsItem(phone: '/iː/', example: 'see', full: '/siː/'),
    PhonicsItem(phone: '/ɪ/', example: 'sit', full: '/sɪt/'),
    PhonicsItem(phone: '/e/', example: 'bed', full: '/bed/'),
    PhonicsItem(phone: '/æ/', example: 'cat', full: '/kæt/'),
    PhonicsItem(phone: '/ɑː/', example: 'car', full: '/kɑːr/'),
    PhonicsItem(phone: '/ɒ/', example: 'hot', full: '/hɒt/'),
    PhonicsItem(phone: '/ɔː/', example: 'door', full: '/dɔːr/'),
    PhonicsItem(phone: '/ʊ/', example: 'book', full: '/bʊk/'),
    PhonicsItem(phone: '/uː/', example: 'moon', full: '/muːn/'),
    PhonicsItem(phone: '/ʌ/', example: 'cup', full: '/kʌp/'),
    PhonicsItem(phone: '/ɜː/', example: 'bird', full: '/bɜːd/'),
    PhonicsItem(phone: '/ə/', example: 'about', full: '/əˈbaʊt/'),
  ]),
  PhonicsGroup(name: '双元音 (8)', items: [
    PhonicsItem(phone: '/eɪ/', example: 'cake', full: '/keɪk/'),
    PhonicsItem(phone: '/aɪ/', example: 'time', full: '/taɪm/'),
    PhonicsItem(phone: '/ɔɪ/', example: 'boy', full: '/bɔɪ/'),
    PhonicsItem(phone: '/aʊ/', example: 'house', full: '/haʊs/'),
    PhonicsItem(phone: '/əʊ/', example: 'home', full: '/həʊm/'),
    PhonicsItem(phone: '/ɪə/', example: 'ear', full: '/ɪər/'),
    PhonicsItem(phone: '/eə/', example: 'hair', full: '/heər/'),
    PhonicsItem(phone: '/ʊə/', example: 'tour', full: '/tʊər/'),
  ]),
  PhonicsGroup(name: '爆破音 (6)', items: [
    PhonicsItem(phone: '/p/', example: 'pen', full: '/pen/'),
    PhonicsItem(phone: '/b/', example: 'book', full: '/bʊk/'),
    PhonicsItem(phone: '/t/', example: 'top', full: '/tɒp/'),
    PhonicsItem(phone: '/d/', example: 'dog', full: '/dɒɡ/'),
    PhonicsItem(phone: '/k/', example: 'cat', full: '/kæt/'),
    PhonicsItem(phone: '/ɡ/', example: 'go', full: '/ɡəʊ/'),
  ]),
  PhonicsGroup(name: '摩擦音 (10)', items: [
    PhonicsItem(phone: '/f/', example: 'fish', full: '/fɪʃ/'),
    PhonicsItem(phone: '/v/', example: 'van', full: '/væn/'),
    PhonicsItem(phone: '/θ/', example: 'think', full: '/θɪŋk/'),
    PhonicsItem(phone: '/ð/', example: 'this', full: '/ðɪs/'),
    PhonicsItem(phone: '/s/', example: 'sun', full: '/sʌn/'),
    PhonicsItem(phone: '/z/', example: 'zoo', full: '/zuː/'),
    PhonicsItem(phone: '/ʃ/', example: 'ship', full: '/ʃɪp/'),
    PhonicsItem(phone: '/ʒ/', example: 'vision', full: '/ˈvɪʒən/'),
    PhonicsItem(phone: '/h/', example: 'hat', full: '/hæt/'),
    PhonicsItem(phone: '/r/', example: 'red', full: '/red/'),
  ]),
  PhonicsGroup(name: '破擦音 (6)', items: [
    PhonicsItem(phone: '/tʃ/', example: 'chips', full: '/tʃɪps/'),
    PhonicsItem(phone: '/dʒ/', example: 'jump', full: '/dʒʌmp/'),
    PhonicsItem(phone: '/tr/', example: 'tree', full: '/triː/'),
    PhonicsItem(phone: '/dr/', example: 'dress', full: '/dres/'),
    PhonicsItem(phone: '/ts/', example: 'cats', full: '/kæts/'),
    PhonicsItem(phone: '/dz/', example: 'beds', full: '/bedz/'),
  ]),
  PhonicsGroup(name: '鼻辅音 (3)', items: [
    PhonicsItem(phone: '/m/', example: 'man', full: '/mæn/'),
    PhonicsItem(phone: '/n/', example: 'nose', full: '/nəʊz/'),
    PhonicsItem(phone: '/ŋ/', example: 'sing', full: '/sɪŋ/'),
  ]),
  PhonicsGroup(name: '舌侧音 (1)', items: [
    PhonicsItem(phone: '/l/', example: 'leg', full: '/leɡ/'),
  ]),
  PhonicsGroup(name: '半元音 (2)', items: [
    PhonicsItem(phone: '/j/', example: 'yes', full: '/jes/'),
    PhonicsItem(phone: '/w/', example: 'wet', full: '/wet/'),
  ]),
];

/// 音标 → 拟音映射（对照 Kotlin phonemeSoundMap）。
/// TTS 无法直接朗读 IPA 符号，每个音标配一个可读文本；
/// 值为近似拟音，个别音标（短元音/个别辅音）依赖真机试听微调。
const Map<String, String> phonemeSoundMap = {
  // 单元音
  '/iː/': 'ee', '/ɪ/': 'ih', '/e/': 'eh', '/æ/': 'ack',
  '/ɑː/': 'ah', '/ɒ/': 'aw', '/ɔː/': 'or', '/ʊ/': 'ook',
  '/uː/': 'oo', '/ʌ/': 'uh', '/ɜː/': 'er', '/ə/': 'uh',
  // 双元音
  '/eɪ/': 'ay', '/aɪ/': 'eye', '/ɔɪ/': 'oy', '/aʊ/': 'ow',
  '/əʊ/': 'oh', '/ɪə/': 'ear', '/eə/': 'air', '/ʊə/': 'oor',
  // 爆破音
  '/p/': 'puh', '/b/': 'buh', '/t/': 'tuh', '/d/': 'duh',
  '/k/': 'kuh', '/ɡ/': 'guh',
  // 摩擦音
  '/f/': 'fuh', '/v/': 'vuh', '/θ/': 'thuh', '/ð/': 'thuh',
  '/s/': 'suh', '/z/': 'zuh', '/ʃ/': 'shuh', '/ʒ/': 'zhuh',
  '/h/': 'huh', '/r/': 'ruh',
  // 破擦音
  '/tʃ/': 'chuh', '/dʒ/': 'juh', '/tr/': 'truh', '/dr/': 'druh',
  '/ts/': 'tsuh', '/dz/': 'dzuh',
  // 鼻辅音
  '/m/': 'muh', '/n/': 'nuh', '/ŋ/': 'nguh',
  // 舌侧音
  '/l/': 'luh',
  // 半元音
  '/j/': 'yuh', '/w/': 'wuh',
};

/// 音标自身拟音文本；未知音标返回 null（调用方兜底读例词）。
String? phonemeOwnSound(String phone) => phonemeSoundMap[phone];

/// 弹窗大字发音文本：字母格读字母名，音标格读自身拟音（映射缺失兜底例词）。
String ownSoundFor(ReferenceCellData cell) => cell.isPhonetic
    ? (phonemeOwnSound(cell.char) ?? cell.example)
    : cell.char.substring(0, 1);

/// 发音文本：字母格先读字母名再读例词（句号停顿），音标格只读例词。
String speakTextFor(ReferenceCellData cell) => cell.isPhonetic
    ? cell.example
    : '${cell.char.substring(0, 1)}. ${cell.example}';
