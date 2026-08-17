const fs = require('fs');
const path = require('path');
const https = require('https');

const targetUrl = 'https://apps.apple.com/app/id6795797415';
const outSvg = path.join(__dirname, 'assets/qr/stayword-app-store.svg');

// Fetch raw QR path from API (without margin)
const apiUrl = `https://api.qrserver.com/v1/create-qr-code/?size=240x240&data=${encodeURIComponent(targetUrl)}&margin=0&format=svg&color=1d1d1f`;

https.get(apiUrl, (res) => {
  let data = '';
  res.on('data', chunk => data += chunk);
  res.on('end', () => {
    // Extract path elements
    const pathMatch = data.match(/<path[^>]*d="([^"]*)"/);
    if (!pathMatch) {
      console.error('Could not extract path');
      return;
    }
    const pathD = pathMatch[1];

    // Build a card with generous white padding
    // Outer canvas: 360x360, QR placed from x=50, y=50 (width=260, height=260)
    // Scale factor: 260 / 240 = 1.0833
    const cardSvg = `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 360 360" width="360" height="360">
  <defs>
    <filter id="soft-shadow" x="-8%" y="-8%" width="116%" height="116%">
      <feDropShadow dx="0" dy="2" stdDeviation="4" flood-color="#000000" flood-opacity="0.12"/>
    </filter>
  </defs>
  <!-- Pure white card with generous breathing space -->
  <rect x="0" y="0" width="360" height="360" rx="20" fill="#ffffff" />
  
  <!-- Centered QR code with ample quiet zone padding -->
  <g transform="translate(48, 48) scale(1.1)">
    <path fill="#1d1d1f" d="${pathD}" />
  </g>
</svg>
`;

    fs.writeFileSync(outSvg, cardSvg, 'utf8');
    console.log('Successfully generated elegant padded QR code to', outSvg);
  });
});
