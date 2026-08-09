// Roam — five locales.
//
// There are barely forty strings in the whole app, because the interface leans
// on icons, numerals, and colour instead of text. That is what makes a sixth
// language a ten-minute job rather than a redesign.
//
// Arabic is RTL. Every rule in styles.css uses logical properties
// (margin-inline-start, not margin-left) so the mirror is free.

export const LOCALES = {
  en: { name: "English",  dir: "ltr", flag: "🇬🇧" },
  es: { name: "Español",  dir: "ltr", flag: "🇪🇸" },
  zh: { name: "中文",      dir: "ltr", flag: "🇨🇳" },
  hi: { name: "हिन्दी",     dir: "ltr", flag: "🇮🇳" },
  ar: { name: "العربية",   dir: "rtl", flag: "🇸🇦" },
};

const STRINGS = {
  en: {
    explore: "Explore", eat: "Eat", beach: "Beaches", attraction: "See", hike: "Walks",
    culture: "Culture", market: "Markets", events: "Events", wifi: "WiFi",
    findGuide: "Find a guide", walk: "Walk", drive: "Drive", boat: "Boat",
    guideOnWay: "Your guide is on the way", min: "min", away: "away",
    stops: "stops", startTour: "Start", endTour: "End tour", listen: "Listen",
    free: "Free", paid: "Paid", stayNearby: "Stay nearby", tickets: "Tickets",
    hiddenGem: "Hidden gem", accessible: "Step-free", noResults: "Nothing here yet",
    worksNow: "Works", brokenNow: "Not working", verified: "Verified",
    arrived: "Arrived", tourComplete: "Tour complete", loading: "Loading",
    whatDoYouLike: "What are you into?", howLocal: "How far off the postcard?",
    yourPace: "Your pace?", done: "Done", startRoute: "Start my route",
    orGuide: "or meet a local guide", yourRoute: "Your route",
    local: "Local", mixed: "Mixed", iconic: "Icons",
    relaxed: "Relaxed", balanced: "Balanced", packed: "Packed",
    nightlife: "Nightlife", art: "Art", history: "History", nature: "Nature",
  },
  es: {
    explore: "Explorar", eat: "Comer", beach: "Playas", attraction: "Ver", hike: "Rutas",
    culture: "Cultura", market: "Mercados", events: "Eventos", wifi: "WiFi",
    findGuide: "Buscar guía", walk: "Caminar", drive: "Coche", boat: "Barco",
    guideOnWay: "Tu guía viene en camino", min: "min", away: "de distancia",
    stops: "paradas", startTour: "Empezar", endTour: "Terminar", listen: "Escuchar",
    free: "Gratis", paid: "De pago", stayNearby: "Dónde dormir", tickets: "Entradas",
    hiddenGem: "Joya oculta", accessible: "Sin escalones", noResults: "Aún no hay nada",
    worksNow: "Funciona", brokenNow: "No funciona", verified: "Verificado",
    arrived: "Llegaste", tourComplete: "Tour completado", loading: "Cargando",
    whatDoYouLike: "¿Qué te interesa?", howLocal: "¿Cuánto turismo?",
    yourPace: "¿Tu ritmo?", done: "Listo", startRoute: "Empezar mi ruta",
    orGuide: "o busca un guía local", yourRoute: "Tu ruta",
    local: "Local", mixed: "Mixto", iconic: "Íconos",
    relaxed: "Tranquilo", balanced: "Normal", packed: "Intenso",
    nightlife: "Noche", art: "Arte", history: "Historia", nature: "Naturaleza",
  },
  zh: {
    explore: "探索", eat: "美食", beach: "海滩", attraction: "景点", hike: "步道",
    culture: "文化", market: "市集", events: "活动", wifi: "无线网络",
    findGuide: "寻找向导", walk: "步行", drive: "驾车", boat: "乘船",
    guideOnWay: "向导正在赶来", min: "分钟", away: "路程",
    stops: "站", startTour: "开始", endTour: "结束", listen: "收听",
    free: "免费", paid: "收费", stayNearby: "附近住宿", tickets: "购票",
    hiddenGem: "小众好去处", accessible: "无障碍", noResults: "暂无内容",
    worksNow: "可用", brokenNow: "不可用", verified: "已验证",
    arrived: "已到达", tourComplete: "行程结束", loading: "加载中",
    whatDoYouLike: "你喜欢什么？", howLocal: "想多本地？",
    yourPace: "你的节奏？", done: "完成", startRoute: "开始我的路线",
    orGuide: "或找一位当地向导", yourRoute: "你的路线",
    local: "本地", mixed: "混合", iconic: "地标",
    relaxed: "轻松", balanced: "适中", packed: "紧凑",
    nightlife: "夜生活", art: "艺术", history: "历史", nature: "自然",
  },
  hi: {
    explore: "खोजें", eat: "खाना", beach: "समुद्र तट", attraction: "देखें", hike: "पैदल रास्ते",
    culture: "संस्कृति", market: "बाज़ार", events: "कार्यक्रम", wifi: "वाईफ़ाई",
    findGuide: "गाइड खोजें", walk: "पैदल", drive: "गाड़ी", boat: "नाव",
    guideOnWay: "आपका गाइड आ रहा है", min: "मिनट", away: "दूर",
    stops: "पड़ाव", startTour: "शुरू करें", endTour: "समाप्त करें", listen: "सुनें",
    free: "मुफ़्त", paid: "सशुल्क", stayNearby: "पास में ठहरें", tickets: "टिकट",
    hiddenGem: "छिपा हुआ रत्न", accessible: "सीढ़ी रहित", noResults: "यहाँ कुछ नहीं है",
    worksNow: "काम करता है", brokenNow: "काम नहीं करता", verified: "सत्यापित",
    arrived: "पहुँच गए", tourComplete: "यात्रा पूरी", loading: "लोड हो रहा है",
    whatDoYouLike: "आपकी रुचि क्या है?", howLocal: "कितना स्थानीय?",
    yourPace: "आपकी गति?", done: "हो गया", startRoute: "मेरा रूट शुरू करें",
    orGuide: "या स्थानीय गाइड से मिलें", yourRoute: "आपका रूट",
    local: "स्थानीय", mixed: "मिश्रित", iconic: "प्रसिद्ध",
    relaxed: "आराम से", balanced: "संतुलित", packed: "व्यस्त",
    nightlife: "नाइटलाइफ़", art: "कला", history: "इतिहास", nature: "प्रकृति",
  },
  ar: {
    explore: "استكشف", eat: "طعام", beach: "شواطئ", attraction: "معالم", hike: "مسارات",
    culture: "ثقافة", market: "أسواق", events: "فعاليات", wifi: "واي فاي",
    findGuide: "ابحث عن مرشد", walk: "مشياً", drive: "بالسيارة", boat: "بالقارب",
    guideOnWay: "مرشدك في الطريق إليك", min: "دقيقة", away: "بعيد",
    stops: "محطات", startTour: "ابدأ", endTour: "إنهاء", listen: "استمع",
    free: "مجاني", paid: "مدفوع", stayNearby: "إقامة قريبة", tickets: "تذاكر",
    hiddenGem: "جوهرة خفية", accessible: "بدون درج", noResults: "لا يوجد شيء هنا بعد",
    worksNow: "يعمل", brokenNow: "لا يعمل", verified: "موثّق",
    arrived: "وصلت", tourComplete: "انتهت الجولة", loading: "جارٍ التحميل",
    whatDoYouLike: "ما الذي يهمك؟", howLocal: "كم تريد الابتعاد عن السياحة؟",
    yourPace: "إيقاعك؟", done: "تم", startRoute: "ابدأ مساري",
    orGuide: "أو قابل مرشداً محلياً", yourRoute: "مسارك",
    local: "محلي", mixed: "مختلط", iconic: "المعالم",
    relaxed: "هادئ", balanced: "متوازن", packed: "مكثّف",
    nightlife: "حياة ليلية", art: "فن", history: "تاريخ", nature: "طبيعة",
  },
};

let current = "en";

export function setLocale(code) {
  current = STRINGS[code] ? code : "en";
  const { dir } = LOCALES[current];
  document.documentElement.lang = current;
  document.documentElement.dir = dir;
  return current;
}

export function getLocale() {
  return current;
}

export function t(key) {
  return STRINGS[current]?.[key] ?? STRINGS.en[key] ?? key;
}
