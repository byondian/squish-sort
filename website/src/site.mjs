// Site-wide settings. Flip APP_LIVE to true on release day (it swaps the
// "coming soon" pill for Apple's official badge and the /go/app-store link).
export const SITE = {
  origin: 'https://squishsort.app',
  APP_LIVE: false,
  appStoreId: '6835495515',
  bundleId: 'com.ianatkinson.squishsort',
  teamId: 'WVLPAK48UN',
  // Operator details used on the legal pages. Leave a field empty and the
  // pages say "on request" rather than printing a blank.
  operator: {
    name: 'Ian Atkinson',
    postal: 'Unit 174986, PO Box 7169, Poole BH15 9EL, United Kingdom',
    phone: '+44 7746 971820',
    country: 'Luxembourg',
  },
  email: { support: 'support@squishsort.app', privacy: 'privacy@squishsort.app' },
  byondianUrl: 'https://byondian.com', // Ian's personal brand site (partners page footer)
  updated: '2026-11-18',
  langs: [
    // legal: true = the legal pages are written and reviewed in this language.
    // Other languages show the English legal pages with a short note in their language.
    { code: 'en', path: '', html: 'en', label: 'English', badge: 'en-us', legal: true },
    { code: 'ja', path: 'ja', html: 'ja', label: '日本語', badge: 'ja-jp', legal: true },
    { code: 'ko', path: 'ko', html: 'ko', label: '한국어', badge: 'ko-kr', legal: true },
    { code: 'zh-hant', path: 'zh-hant', html: 'zh-Hant', label: '繁體中文', badge: 'zh-tw', legal: true },
    { code: 'zh-hans', path: 'zh-hans', html: 'zh-Hans', label: '简体中文', badge: 'zh-cn' },
    { code: 'es', path: 'es', html: 'es', label: 'Español', badge: 'es-es' },
    { code: 'fr', path: 'fr', html: 'fr', label: 'Français', badge: 'fr-fr' },
    { code: 'de', path: 'de', html: 'de', label: 'Deutsch', badge: 'de-de' },
    { code: 'it', path: 'it', html: 'it', label: 'Italiano', badge: 'it-it' },
    { code: 'pt-br', path: 'pt-br', html: 'pt-BR', label: 'Português (Brasil)', badge: 'pt-br' },
    { code: 'nl', path: 'nl', html: 'nl', label: 'Nederlands', badge: 'nl-nl' },
    { code: 'pl', path: 'pl', html: 'pl', label: 'Polski', badge: 'pl-pl' },
    { code: 'sv', path: 'sv', html: 'sv', label: 'Svenska', badge: 'sv-se' },
    { code: 'nb', path: 'nb', html: 'nb', label: 'Norsk', badge: 'nb-no' },
    { code: 'da', path: 'da', html: 'da', label: 'Dansk', badge: 'da-dk' },
    { code: 'tr', path: 'tr', html: 'tr', label: 'Türkçe', badge: 'tr-tr' },
    { code: 'id', path: 'id', html: 'id', label: 'Bahasa Indonesia', badge: 'id-id' },
    { code: 'th', path: 'th', html: 'th', label: 'ไทย', badge: 'th-th' },
  ],
  legalPages: ['privacy', 'terms', 'ads', 'purchases', 'parents', 'delete', 'cookies', 'accessibility', 'imprint'],
};
