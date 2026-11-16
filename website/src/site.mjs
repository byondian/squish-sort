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
    postal: '', // TODO(Ian): the address declared as DSA trader in App Store Connect
    phone: '', // TODO(Ian): the phone number declared as DSA trader
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
