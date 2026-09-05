// Démo interactive : trois profils de Dock, changement au clic.

const ICONS = {
  mail: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="5.5" width="18" height="13" rx="2.5"/><path d="M3.5 7l8.5 6 8.5-6"/></svg>',
  calendar: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><rect x="3.5" y="5" width="17" height="15" rx="2.5"/><path d="M3.5 10h17M8 3v4M16 3v4"/></svg>',
  chat: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><path d="M4 6.5A2.5 2.5 0 0 1 6.5 4h11A2.5 2.5 0 0 1 20 6.5v8a2.5 2.5 0 0 1-2.5 2.5H10l-4.5 3.5V17H6.5A2.5 2.5 0 0 1 4 14.5z"/></svg>',
  terminal: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5 7l5 5-5 5M12 17h7"/></svg>',
  code: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M8 7l-5 5 5 5M16 7l5 5-5 5M14 4l-4 16"/></svg>',
  globe: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17M12 3.5c3 3 3 14 0 17M12 3.5c-3 3-3 14 0 17"/></svg>',
  note: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><rect x="5" y="3.5" width="14" height="17" rx="2.5"/><path d="M8.5 9h7M8.5 13h7M8.5 17h4"/></svg>',
  music: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M9 18V6l10-2v12"/><circle cx="6.5" cy="18" r="2.5"/><circle cx="16.5" cy="16" r="2.5"/></svg>',
  photo: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><rect x="3.5" y="5" width="17" height="14" rx="2.5"/><path d="M3.5 15.5l5-5 4 4 3-3 5 5"/><circle cx="16" cy="9" r="1.4" fill="currentColor" stroke="none"/></svg>',
  game: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M7 7h10a5 5 0 0 1 4.9 6l-.6 3a2.5 2.5 0 0 1-4.3 1.2L15 15H9l-2 2.2A2.5 2.5 0 0 1 2.7 16l-.6-3A5 5 0 0 1 7 7z"/><path d="M8 10v3M6.5 11.5h3M15.5 11h.01M17.5 12.5h.01"/></svg>',
  pen: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 20l4-1 10-10-3-3L5 16z"/><path d="M13 8l3 3"/></svg>',
  film: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="3.5" y="4.5" width="17" height="15" rx="2.5"/><path d="M3.5 9h17M3.5 15h17M8 4.5v15M16 4.5v15"/></svg>',
  book: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><path d="M4 5.5A1.5 1.5 0 0 1 5.5 4H11a2 2 0 0 1 2 2v14a2 2 0 0 0-2-2H4z"/><path d="M20 5.5A1.5 1.5 0 0 0 18.5 4H13a2 2 0 0 0-2 2v14a2 2 0 0 1 2-2h7z"/></svg>',
  finder: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><rect x="4" y="4" width="16" height="16" rx="4"/><path d="M12 4v16M8.5 9.5v1.5M15.5 9.5v1.5M8 15c1.2 1.2 2.4 1.7 4 1.7s2.8-.5 4-1.7"/></svg>',
  settings: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="12" r="3"/><path d="M12 3.5v2.2M12 18.3v2.2M3.5 12h2.2M18.3 12h2.2M6 6l1.6 1.6M16.4 16.4L18 18M6 18l1.6-1.6M16.4 7.6L18 6"/></svg>',
};

// Dégradés "façon icône macOS", volontairement abstraits.
const TINTS = {
  blue:   'linear-gradient(145deg, #5ac8fa, #1e6fe8)',
  indigo: 'linear-gradient(145deg, #7d8bff, #4a3fd6)',
  red:    'linear-gradient(145deg, #ff7a6b, #e0342b)',
  orange: 'linear-gradient(145deg, #ffb340, #f2760a)',
  green:  'linear-gradient(145deg, #6ee08a, #1f9f4b)',
  teal:   'linear-gradient(145deg, #5ee2d9, #17a2a6)',
  purple: 'linear-gradient(145deg, #d58bff, #8a3fd6)',
  pink:   'linear-gradient(145deg, #ff8ac1, #e0348a)',
  gray:   'linear-gradient(145deg, #8e8e93, #4c4c52)',
  dark:   'linear-gradient(145deg, #3a3a3f, #141416)',
  yellow: 'linear-gradient(145deg, #ffd84d, #f5a300)',
};

const app = (icon, tint) => ({ type: 'app', icon, tint });
const spacer = (small = false) => ({ type: 'spacer', small });

const PROFILES = [
  {
    name: 'Travail',
    color: '#4A90E2',
    items: [
      app('finder', 'blue'), app('mail', 'blue'), app('calendar', 'red'), app('chat', 'purple'),
      spacer(), app('terminal', 'dark'), app('code', 'indigo'), app('globe', 'teal'), app('note', 'yellow'),
    ],
  },
  {
    name: 'Perso',
    color: '#50C878',
    items: [
      app('finder', 'blue'), app('globe', 'teal'), app('music', 'pink'), app('photo', 'orange'),
      spacer(), app('book', 'orange'), app('game', 'green'),
    ],
  },
  {
    name: 'Création',
    color: '#9B59B6',
    items: [
      app('finder', 'blue'), app('pen', 'purple'), app('photo', 'orange'), app('film', 'indigo'),
      app('music', 'pink'), spacer(true), app('note', 'yellow'),
    ],
  },
];

const dock = document.getElementById('dock');
const dropdown = document.getElementById('dropdown');
const statusName = document.getElementById('status-name');
let active = 0;

function renderDock(profile) {
  dock.innerHTML = '';
  let i = 0;
  for (const item of profile.items) {
    if (item.type === 'spacer') {
      const el = document.createElement('div');
      el.className = 'dock-spacer' + (item.small ? ' small' : '');
      dock.appendChild(el);
      continue;
    }
    const el = document.createElement('div');
    el.className = 'dock-app';
    el.style.background = TINTS[item.tint];
    el.style.setProperty('--i', i++);
    el.innerHTML = ICONS[item.icon];
    dock.appendChild(el);
  }
  const divider = document.createElement('div');
  divider.className = 'dock-divider';
  dock.appendChild(divider);
  const settings = document.createElement('div');
  settings.className = 'dock-app';
  settings.style.background = TINTS.gray;
  settings.style.setProperty('--i', i);
  settings.innerHTML = ICONS.settings;
  dock.appendChild(settings);
  fitDock();
}

// Réduit le Dock s'il est plus large que la zone de démo (petits écrans).
function fitDock() {
  const available = dock.parentElement.clientWidth - 24;
  dock.style.transform = '';
  const width = dock.scrollWidth;
  if (width > available) {
    dock.style.transform = `scale(${(available / width).toFixed(3)})`;
  }
}
window.addEventListener('resize', fitDock);

function renderDropdown() {
  dropdown.innerHTML = '';
  PROFILES.forEach((p, index) => {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'dd-item';
    btn.setAttribute('role', 'option');
    btn.setAttribute('aria-selected', index === active ? 'true' : 'false');
    btn.innerHTML =
      `<span class="dd-check">✓</span>` +
      `<span class="dd-dot" style="background:${p.color}"></span>` +
      `<span class="dd-name">${p.name}</span>` +
      `<span class="dd-key">⌘${index + 1}</span>`;
    btn.addEventListener('click', () => select(index));
    dropdown.appendChild(btn);
  });
  const sep = document.createElement('div');
  sep.className = 'dd-sep';
  dropdown.appendChild(sep);
  const more = document.createElement('div');
  more.className = 'dd-item dd-muted';
  more.innerHTML = `<span class="dd-check"></span><span class="dd-name">Gérer les profils…</span><span class="dd-key">⌘,</span>`;
  dropdown.appendChild(more);
}

function select(index, { user = true } = {}) {
  if (index === active && user) return;
  active = index;
  const profile = PROFILES[active];
  statusName.textContent = profile.name;
  renderDock(profile);
  renderDropdown();
  if (user) stopAutoCycle();
}

// Défilement automatique tant que l'utilisateur n'a pas cliqué.
let timer = null;
function startAutoCycle() {
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  timer = setInterval(() => select((active + 1) % PROFILES.length, { user: false }), 3200);
}
function stopAutoCycle() {
  if (timer) { clearInterval(timer); timer = null; }
}

// Raccourcis ⌘1-3 quand la démo est visible à l'écran.
document.addEventListener('keydown', (e) => {
  if (!(e.metaKey || e.ctrlKey)) return;
  const n = Number(e.key);
  if (n >= 1 && n <= PROFILES.length) {
    const rect = dock.getBoundingClientRect();
    if (rect.bottom < 0 || rect.top > window.innerHeight) return;
    e.preventDefault();
    select(n - 1);
  }
});

document.getElementById('year').textContent = String(new Date().getFullYear());

select(0, { user: false });
startAutoCycle();
