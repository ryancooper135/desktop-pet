// Волна 51: условный Шиба для макетов (в приложении — PixelDog из кода). Поза → SVG.
// <span data-dog="bath" data-w="90"></span> — заменяется картинкой при загрузке.
(function () {
  const O = '#e0803a', W = '#f7e6cc', K = '#2b2622', B = '#9fd3ff';
  const head = (x, y, closed) => `
    <polygon points="${x - 13},${y - 6} ${x - 9},${y - 20} ${x - 3},${y - 9}" fill="${O}"/>
    <polygon points="${x + 13},${y - 6} ${x + 9},${y - 20} ${x + 3},${y - 9}" fill="${O}"/>
    <ellipse cx="${x}" cy="${y}" rx="15" ry="13" fill="${O}"/>
    <ellipse cx="${x}" cy="${y + 5}" rx="10" ry="7" fill="${W}"/>
    ${closed
      ? `<path d="M${x - 9} ${y - 2} q3 3 6 0 M${x + 3} ${y - 2} q3 3 6 0" stroke="${K}" stroke-width="1.8" fill="none"/>`
      : `<circle cx="${x - 6}" cy="${y - 2}" r="2.2" fill="${K}"/><circle cx="${x + 6}" cy="${y - 2}" r="2.2" fill="${K}"/>`}
    <ellipse cx="${x}" cy="${y + 3}" rx="2.4" ry="1.6" fill="${K}"/>`;
  const poses = {
    sit: () => `
      <ellipse cx="54" cy="58" rx="20" ry="17" fill="${O}"/>
      <ellipse cx="50" cy="60" rx="10" ry="12" fill="${W}"/>
      <path d="M72 56 q12 -8 6 -18 q-4 6 -8 8" fill="${O}"/>
      <rect x="40" y="70" width="7" height="6" rx="3" fill="${W}"/><rect x="55" y="70" width="7" height="6" rx="3" fill="${W}"/>
      ${head(50, 33)}`,
    run: () => `
      <path d="M8 40 h14 M4 50 h16 M10 60 h12" stroke="#c9b8a4" stroke-width="2.5" stroke-linecap="round"/>
      <ellipse cx="48" cy="52" rx="24" ry="12" fill="${O}"/>
      <ellipse cx="50" cy="57" rx="14" ry="6" fill="${W}"/>
      <path d="M30 48 q-10 -10 -4 -16 q2 8 8 10" fill="${O}"/>
      <path d="M32 58 l-10 10 M40 60 l-4 12 M60 60 l8 10 M66 56 l12 6" stroke="${O}" stroke-width="6" stroke-linecap="round"/>
      ${head(72, 38)}`,
    sleep: () => `
      <ellipse cx="50" cy="62" rx="30" ry="11" fill="${O}"/>
      <ellipse cx="54" cy="66" rx="18" ry="5" fill="${W}"/>
      <path d="M20 62 q-6 -10 6 -12" fill="${O}" stroke="${O}" stroke-width="4"/>
      ${head(70, 52, true)}
      <text x="74" y="26" font-size="12" font-weight="700" fill="${'#7b6fd6'}" font-family="sans-serif">z</text>
      <text x="83" y="16" font-size="16" font-weight="700" fill="${'#7b6fd6'}" font-family="sans-serif">Z</text>`,
    bath: () => `
      ${head(50, 34)}
      <circle cx="30" cy="20" r="5" fill="none" stroke="${B}" stroke-width="2"/>
      <circle cx="72" cy="14" r="4" fill="none" stroke="${B}" stroke-width="2"/>
      <circle cx="80" cy="30" r="3" fill="none" stroke="${B}" stroke-width="2"/>
      <ellipse cx="50" cy="50" rx="34" ry="8" fill="#fff"/>
      <circle cx="26" cy="48" r="6" fill="#fff"/><circle cx="40" cy="46" r="7" fill="#fff"/>
      <circle cx="62" cy="46" r="7" fill="#fff"/><circle cx="75" cy="48" r="6" fill="#fff"/>
      <path d="M14 50 h72 l-6 22 q-2 4 -6 4 h-48 q-4 0 -6 -4z" fill="${'#3d9be0'}"/>`,
    bowl: () => `
      <ellipse cx="54" cy="58" rx="20" ry="17" fill="${O}"/>
      <ellipse cx="50" cy="60" rx="10" ry="12" fill="${W}"/>
      ${head(48, 33)}
      <path d="M66 66 h26 l-4 9 h-18z" fill="${'#d9534f'}"/>`,
  };
  document.querySelectorAll('[data-dog]').forEach(el => {
    const p = el.dataset.dog, w = +(el.dataset.w || 90);
    el.outerHTML = `<svg class="dog" width="${w}" height="${w * 0.8}" viewBox="0 0 100 80">${(poses[p] || poses.sit)()}</svg>`;
  });
})();
