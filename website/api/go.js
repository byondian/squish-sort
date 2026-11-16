// /go/app-store?from=<tag>: sends visitors to the App Store with a campaign
// token so App Store Connect shows which link they came from.
const APP_ID = '6835495515';
export default function handler(req, res) {
  const url = new URL(req.url, 'https://squishsort.app');
  const from = (url.searchParams.get('from') || 'site').replace(/[^a-z0-9-]/gi, '').slice(0, 40) || 'site';
  const pt = process.env.APP_STORE_PROVIDER_TOKEN || '';
  const dest = `https://apps.apple.com/app/apple-store/id${APP_ID}?${pt ? `pt=${encodeURIComponent(pt)}&` : ''}ct=${encodeURIComponent(from)}&mt=8`;
  res.setHeader('Cache-Control', 'no-store');
  res.writeHead(302, { Location: dest }); res.end();
}
