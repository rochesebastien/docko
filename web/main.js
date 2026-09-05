// Démo interactive : menu de la barre des menus + Dock façon macOS.

const ICON_DIR = 'assets/icons/';

// Chaque app : nom affiché, fichier d'icône, fond de la tuile.
// `full` : l'icône remplit toute la tuile (déjà dessinée en squircle).
// `inv`  : glyphe noir à inverser en blanc.
const APPS = {
  arc:      { label: 'Arc',              icon: 'arc.svg',      bg: '#ffffff' },
  slack:    { label: 'Slack',            icon: 'slack.svg',    bg: '#ffffff' },
  linear:   { label: 'Linear',           icon: 'linear.svg',   bg: '#111111', inv: true },
  openai:   { label: 'ChatGPT',          icon: 'openai.svg',   bg: '#ffffff' },
  github:   { label: 'GitHub Desktop',   icon: 'github.svg',   bg: '#ffffff' },
  figma:    { label: 'Figma',            icon: 'figma.svg',    bg: '#1e1e1e' },
  notion:   { label: 'Notion',           icon: 'notion.svg',   bg: '#ffffff' },
  safari:   { label: 'Safari',           icon: 'safari.svg',   full: true },
  spotify:  { label: 'Spotify',          icon: 'spotify.svg',  bg: '#000000' },
  discord:  { label: 'Discord',          icon: 'discord.svg',  bg: '#5865f2', inv: true },
  chrome:   { label: 'Google Chrome',    icon: 'chrome.svg',   bg: '#ffffff' },
  obsidian: { label: 'Obsidian',         icon: 'obsidian.svg', bg: '#1b1b1f' },
  cursor:   { label: 'Cursor',           icon: 'cursor.svg',   bg: '#000000' },
  claude:   { label: 'Claude',           icon: 'claude.svg',   bg: '#ffffff' },
};

const PROFILES = [
  {
    name: 'Travail',
    color: '#6d7cff',
    items: ['arc', 'slack', 'linear', 'notion', 'openai', 'github'],
  },
  {
    name: 'Perso',
    color: '#ef5da8',
    items: ['safari', 'spotify', 'discord', 'obsidian', 'claude'],
  },
  {
    name: 'Création',
    color: '#f59e0b',
    items: ['chrome', 'figma', 'cursor', 'claude', 'spotify'],
  },
];

const demo = document.getElementById('demo');
const dock = document.getElementById('dock');
const dropdown = document.getElementById('dropdown');
const ddList = document.getElementById('dd-list');
const statusBtn = document.getElementById('status-btn');
const statusName = document.getElementById('status-name');
const toggleName = document.getElementById('toggle-name');

let active = 0;
let switching = false;

// ---------- Rendu du Dock ----------

function appTile(key) {
  const app = APPS[key];
  const tile = document.createElement('div');
  tile.className = 'dock-app' + (app.full ? ' full' : '');
  tile.dataset.label = app.label;
  if (app.bg) tile.style.background = app.bg;
  const img = document.createElement('img');
  img.src = ICON_DIR + app.icon;
  img.alt = '';
  img.draggable = false;
  if (app.inv) img.className = 'inv';
  tile.appendChild(img);
  return tile;
}

function dockoTile() {
  const tile = document.createElement('div');
  tile.className = 'dock-app full';
  tile.dataset.label = 'Docko';
  const img = document.createElement('img');
  img.src = 'assets/docko-macos.png';
  img.alt = '';
  img.draggable = false;
  tile.appendChild(img);
  return tile;
}

function buildDock(profile) {
  const frag = document.createDocumentFragment();
  let i = 0;
  for (const key of profile.items) {
    const item = document.createElement('div');
    item.className = 'dock-item';
    item.style.setProperty('--i', i++);
    item.appendChild(appTile(key));
    frag.appendChild(item);
  }
  const divider = document.createElement('div');
  divider.className = 'dock-divider';
  frag.appendChild(divider);

  const docko = document.createElement('div');
  docko.className = 'dock-item running';
  docko.style.setProperty('--i', i);
  docko.appendChild(dockoTile());
  frag.appendChild(docko);
  return frag;
}

function renderDock(profile, { animateOut = false } = {}) {
  const items = Array.from(dock.querySelectorAll('.dock-item'));
  const swap = () => {
    dock.innerHTML = '';
    dock.appendChild(buildDock(profile));
    fitDock();
    switching = false;
  };
  if (animateOut && items.length && !reducedMotion()) {
    switching = true;
    items.forEach((el) => el.classList.add('leaving'));
    setTimeout(swap, 170);
  } else {
    swap();
  }
}

// Réduit le Dock s'il dépasse la largeur de la démo (petits écrans).
function fitDock() {
  const available = dock.parentElement.clientWidth - 24;
  dock.style.transform = '';
  const width = dock.scrollWidth;
  if (width > available) dock.style.transform = `scale(${(available / width).toFixed(3)})`;
}
window.addEventListener('resize', fitDock);

// ---------- Agrandissement façon macOS ----------

const MAGNIFY_RANGE = 130;
const MAGNIFY_MAX = 0.5;

dock.addEventListener('mousemove', (e) => {
  if (switching || reducedMotion()) return;
  const dockRect = dock.getBoundingClientRect();
  const scale = dockRect.width / dock.offsetWidth; // compense le scale mobile
  for (const tile of dock.querySelectorAll('.dock-app')) {
    const item = tile.parentElement;
    const center = dockRect.left + (item.offsetLeft + item.offsetWidth / 2) * scale;
    const distance = Math.abs(e.clientX - center) / scale;
    const factor = Math.max(0, 1 - distance / MAGNIFY_RANGE);
    tile.style.setProperty('--s', (1 + MAGNIFY_MAX * factor * factor).toFixed(3));
  }
});
dock.addEventListener('mouseleave', () => {
  for (const tile of dock.querySelectorAll('.dock-app')) tile.style.setProperty('--s', 1);
});

// ---------- Menu ----------

function renderMenu() {
  ddList.innerHTML = '';
  PROFILES.forEach((p, index) => {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'dd-item';
    btn.setAttribute('role', 'option');
    btn.setAttribute('aria-selected', index === active ? 'true' : 'false');
    btn.innerHTML =
      `<span class="dd-check">✓</span>` +
      `<span class="dd-swatch" style="background:${p.color}"></span>` +
      `<span class="dd-name">${p.name}</span>` +
      `<span class="dd-key">⌘${index + 1}</span>`;
    btn.addEventListener('click', () => {
      stopAutoDemo();
      select(index);
      setTimeout(closeMenu, 260);
    });
    ddList.appendChild(btn);
  });
}

function positionMenu() {
  // Aligne le bord droit du menu sous l'item Docko de la barre.
  const right = demo.clientWidth - (statusBtn.offsetLeft + statusBtn.offsetWidth);
  dropdown.style.right = `${Math.max(8, right)}px`;
}
window.addEventListener('resize', positionMenu);

function openMenu() {
  positionMenu();
  dropdown.hidden = false;
  statusBtn.setAttribute('aria-expanded', 'true');
}
function closeMenu() {
  dropdown.hidden = true;
  statusBtn.setAttribute('aria-expanded', 'false');
}
function toggleMenu() {
  dropdown.hidden ? openMenu() : closeMenu();
}

statusBtn.addEventListener('click', () => {
  stopAutoDemo();
  toggleMenu();
});
document.addEventListener('click', (e) => {
  if (!dropdown.hidden && !dropdown.contains(e.target) && !statusBtn.contains(e.target)) closeMenu();
});
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') closeMenu();
});

document.getElementById('dd-manage').addEventListener('click', () => {
  stopAutoDemo();
  closeMenu();
});

toggleName.addEventListener('change', () => {
  stopAutoDemo();
  statusBtn.classList.toggle('no-name', !toggleName.checked);
});

// ---------- Sélection ----------

function select(index, { animate = true } = {}) {
  const changed = index !== active;
  active = index;
  const profile = PROFILES[active];
  statusName.textContent = profile.name;
  renderMenu();
  if (changed || !dock.childElementCount) renderDock(profile, { animateOut: animate && changed });
}

// ---------- Démo automatique ----------

let autoTimer = null;
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

async function autoDemoLoop() {
  while (autoTimer) {
    await wait(3400);
    if (!autoTimer) break;
    openMenu();
    await wait(900);
    if (!autoTimer) break;
    select((active + 1) % PROFILES.length);
    await wait(700);
    if (!autoTimer) break;
    closeMenu();
  }
}
function startAutoDemo() {
  if (reducedMotion()) return;
  autoTimer = true;
  autoDemoLoop();
}
function stopAutoDemo() {
  autoTimer = null;
}

demo.addEventListener('pointerdown', stopAutoDemo, { once: true });

function reducedMotion() {
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches;
}

// Raccourcis ⌘1-3 quand la démo est visible.
document.addEventListener('keydown', (e) => {
  if (!(e.metaKey || e.ctrlKey)) return;
  const n = Number(e.key);
  if (n >= 1 && n <= PROFILES.length) {
    const rect = demo.getBoundingClientRect();
    if (rect.bottom < 0 || rect.top > window.innerHeight) return;
    e.preventDefault();
    stopAutoDemo();
    select(n - 1);
  }
});

document.getElementById('year').textContent = String(new Date().getFullYear());

select(0, { animate: false });
startAutoDemo();
