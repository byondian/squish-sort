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
    phone: '', // TODO(Ian): add once the UK number works
    country: 'Luxembourg',
  },
  email: { support: 'support@squishsort.app', privacy: 'privacy@squishsort.app' },
  updated: '2026-11-16',
  langs: [
    { code: 'en', path: '', html: 'en', label: 'English', badge: 'en-us' },
    { code: 'ja', path: 'ja', html: 'ja', label: '日本語', badge: 'ja-jp' },
    { code: 'ko', path: 'ko', html: 'ko', label: '한국어', badge: 'ko-kr' },
    { code: 'zh-hant', path: 'zh-hant', html: 'zh-Hant', label: '繁體中文', badge: 'zh-tw' },
  ],
  legalPages: ['privacy', 'terms', 'ads', 'purchases', 'parents', 'delete', 'cookies', 'accessibility', 'imprint'],
};
