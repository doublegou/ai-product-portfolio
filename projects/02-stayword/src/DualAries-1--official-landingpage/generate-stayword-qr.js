const fs = require('fs');
const path = require('path');
const https = require('https');

const targetUrl = 'https://apps.apple.com/app/id6795797415';
const outSvg = path.join(__dirname, 'assets/qr/stayword-app-store.svg');

// Generate QR Code with Level H error correction (30% redundancy for center logo support)
const apiUrl = `https://api.qrserver.com/v1/create-qr-code/?size=260x260&data=${encodeURIComponent(targetUrl)}&margin=0&ecc=H&format=svg&color=1d1d1f`;

https.get(apiUrl, (res) => {
  let data = '';
  res.on('data', chunk => data += chunk);
  res.on('end', () => {
    const pathMatch = data.match(/<path[^>]*d="([^"]*)"/);
    if (!pathMatch) {
      console.error('Could not extract path');
      return;
    }
    const pathD = pathMatch[1];

    // Canvas 360x360, QR matrix 264x264 centered from x=48, y=48
    const cardSvg = `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 360 360" width="360" height="360">
  <!-- Pure white card with generous breathing space -->
  <rect x="0" y="0" width="360" height="360" rx="20" fill="#ffffff" />
  
  <!-- Centered QR code with High ECC (Level H) -->
  <g transform="translate(48, 48) scale(1.015)">
    <path fill="#1d1d1f" d="${pathD}" />
  </g>
</svg>
`;

    fs.writeFileSync(outSvg, cardSvg, 'utf8');
    console.log('Saved Level H StayWord QR SVG to', outSvg);
  });
});
