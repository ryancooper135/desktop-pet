// Волна 57: контурные иконки команд в духе SF Symbols — только для макетов. В приложении сами SF Symbols:
// Сидеть dog.fill · Лапу pawprint.fill · Лежать bed.double.fill · Голос speaker.wave.2.fill · Кружись arrow.trianglehead.2.clockwise.rotate.90
// Дай пять hand.raised.fill · Притворись спящим powersleep · Ползи tortoise.fill; значки: star.fill, lock.fill, moon.zzz.fill, bubbles.and.sparkles.fill, figure.walk
document.body.insertAdjacentHTML('afterbegin', `<svg width="0" height="0" style="position:absolute">
  <symbol id="sit" viewBox="0 0 24 24"><path d="M8 20v-6.5l-2.6-2.2a2 2 0 0 1 .3-3.2L8.6 6.6 9.4 4l2 2.2 1.6-.4"/><path d="M8.6 13.5c2-.7 5.4-.6 7.4 1.4 1.4 1.4 1.6 3.4 1.6 5.1H8M13 20v-3"/><path d="M17.6 18.5 20 17"/></symbol>
  <symbol id="paw" viewBox="0 0 24 24"><ellipse cx="12" cy="15.5" rx="4.5" ry="3.8"/><circle cx="6.5" cy="10" r="1.8"/><circle cx="17.5" cy="10" r="1.8"/><circle cx="9.5" cy="6" r="1.8"/><circle cx="14.5" cy="6" r="1.8"/></symbol>
  <symbol id="lie" viewBox="0 0 24 24"><path d="M3 18V7M3 14h18v4M21 14v-2.5a2.5 2.5 0 0 0-2.5-2.5H11v5"/><rect x="5" y="10" width="4" height="3" rx="1.2"/></symbol>
  <symbol id="speak" viewBox="0 0 24 24"><path d="M4 9.5h3l4.5-3.5v12L7 14.5H4z"/><path d="M15 9a4 4 0 0 1 0 6M17.6 6.6a7.5 7.5 0 0 1 0 10.8"/></symbol>
  <symbol id="spin" viewBox="0 0 24 24"><path d="M19.5 12A7.5 7.5 0 0 1 6 16.5M4.5 12A7.5 7.5 0 0 1 18 7.5"/><path d="M18 3.5v4h-4M6 20.5v-4h4"/></symbol>
  <symbol id="five" viewBox="0 0 24 24"><path d="M8 13V6a1.4 1.4 0 0 1 2.8 0v5M10.8 10.5V4.5a1.4 1.4 0 0 1 2.8 0v6M13.6 10.5V5.5a1.4 1.4 0 0 1 2.8 0V12M16.4 11V8a1.4 1.4 0 0 1 2.8 0v6.5a7 7 0 0 1-7 6.5c-2.6 0-4-1.2-5.4-3.2L4.6 14.4a1.5 1.5 0 0 1 2.4-1.8L8 14"/></symbol>
  <symbol id="dead" viewBox="0 0 24 24"><circle cx="11" cy="13" r="7.5"/><path d="M11 9v4l2.5 1.5"/><path d="M15.5 3.5h4l-4 4h4"/></symbol>
  <symbol id="crawl" viewBox="0 0 24 24"><path d="M4 15a8 6 0 0 1 14-3.5"/><path d="M4 15h15.5a2.5 2.5 0 0 0 0-5H18"/><path d="M6.5 15l-1 3M10 15v3M13.5 15l1 3"/><path d="M7 11.5l2.5-3M11 10.5V7.8M14.5 11.5l-1-2.8"/></symbol>
  <symbol id="star" viewBox="0 0 24 24"><path d="M12 3.2l2.7 5.6 6.1.8-4.5 4.2 1.1 6-5.4-2.9-5.4 2.9 1.1-6-4.5-4.2 6.1-.8z"/></symbol>
  <symbol id="lock" viewBox="0 0 24 24"><rect x="5" y="10.5" width="14" height="10" rx="2.5"/><path d="M8 10.5V8a4 4 0 0 1 8 0v2.5" fill="none" stroke="currentColor" stroke-width="2.4"/></symbol>
  <symbol id="nap" viewBox="0 0 24 24"><path d="M17 14.5A7 7 0 0 1 8.5 5a7 7 0 1 0 8.5 9.5z"/><path d="M14 3.5h4l-4 4h4" fill="none" stroke="currentColor" stroke-width="1.8"/></symbol>
  <symbol id="bath" viewBox="0 0 24 24"><circle cx="9" cy="14" r="5"/><circle cx="16.5" cy="9" r="3"/><circle cx="17" cy="17" r="1.8"/></symbol>
  <symbol id="walk" viewBox="0 0 24 24"><circle cx="13" cy="4.5" r="1.8"/><path d="M10 21l2.4-6.5L15 17v4M8 11.5l3-3.2 3.4 1.2 2 3M12.4 14.5 11 8.3"/></symbol>
  <symbol id="heart" viewBox="0 0 24 24"><path d="M12 20s-7.5-4.6-7.5-10.2A4.1 4.1 0 0 1 12 7.3a4.1 4.1 0 0 1 7.5 2.5C19.5 15.4 12 20 12 20z"/></symbol>
  <symbol id="brush" viewBox="0 0 24 24"><path d="M4 20c3 0 5-1 5-3.5a2.5 2.5 0 0 0-5 0V20zM9 15l10-10a1.5 1.5 0 0 1 2 2L11 17"/></symbol>
  <symbol id="bowl" viewBox="0 0 24 24"><path d="M3 12h18a9 8 0 0 1-18 0z"/><path d="M9 8c0-1.6 1.6-1.6 1.6-3.2M13.5 8c0-1.6 1.6-1.6 1.6-3.2"/></symbol>
  <symbol id="ball" viewBox="0 0 24 24"><circle cx="12" cy="12" r="8.5"/><path d="M5 7.5c4 1.4 5.6 5.6 4.4 12M19 16.5c-4-1.4-5.6-5.6-4.4-12"/></symbol>
  <symbol id="drop" viewBox="0 0 24 24"><path d="M12 3.5s6 6.4 6 10.5a6 6 0 0 1-12 0c0-4.1 6-10.5 6-10.5z"/></symbol>
</svg>`);

// Кольцо прогресса: <span data-ring="0.6"></span> внутри .disc
function rings() {
  document.querySelectorAll('[data-ring]').forEach(el => {
    const p = +el.dataset.ring, c = el.dataset.c || '#f08a5d', r = 46, L = 2 * Math.PI * r;
    el.outerHTML = `<svg class="ring" viewBox="0 0 100 100"><circle cx="50" cy="50" r="${r}" fill="none" stroke="#efe2d6" stroke-width="5"/>` +
      (p > 0 ? `<circle cx="50" cy="50" r="${r}" fill="none" stroke="${c}" stroke-width="5" stroke-linecap="round" stroke-dasharray="${L * p} ${L}"/>` : '') + `</svg>`;
  });
}

// Команда: <div data-cmd="sit" data-st="learned | p0.4 | lock5 | grey-nap" data-l="Сидеть" data-d="74"></div>
function cmds() {
  document.querySelectorAll('[data-cmd]').forEach(el => {
    const id = el.dataset.cmd, st = el.dataset.st || '', l = el.dataset.l || '', d = el.dataset.d;
    let cls = 'cmd', ring = '', badge = '', lvl = '';
    if (st === 'learned') { cls += ' learned'; badge = `<div class="badge" style="color:#f2bf4a"><svg class="f"><use href="#star"/></svg></div>`; }
    else if (st.startsWith('p')) { ring = `<span data-ring="${st.slice(1)}"></span>`; }
    else if (st.startsWith('lock')) { cls += ' locked'; lvl = `<div class="lvl"><svg class="f" style="width:11px;height:11px"><use href="#lock"/></svg>${st.slice(4)}</div>`; }
    else if (st.startsWith('grey')) {
      cls += ' grey'; const k = st.split('-')[1], c = { nap: '#7b6fd6', bath: '#6f9fd8', walk: '#9b7fd8' }[k];
      badge = `<div class="badge" style="color:${c}"><svg class="${k === 'walk' ? 'i' : 'f'}"><use href="#${k}"/></svg></div>`;
    }
    if (el.dataset.press) cls += ' press';
    el.outerHTML = `<div class="${cls}" ${d ? `style="--d:${d}px"` : ''}><div class="disc">${ring}<svg class="i"><use href="#${id}"/></svg>${badge}${lvl}</div>${l ? `<div class="lbl">${l}</div>` : ''}</div>`;
  });
  rings();
}
