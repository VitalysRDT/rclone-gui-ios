/* ════════════════════════════════════════════════════════════════════
   Rclone GUI — public forum (ideas, bugs, questions)

   Source of docs/forum.js. After editing, recompile with Babel
   (preset-react, runtime "classic") — the page loads plain JS, no CDN
   and no runtime transform. See docs/README-build.md.
   ════════════════════════════════════════════════════════════════════ */

const API = 'https://rclone-gui-trial.vercel.app/api/forum';
const GITHUB_URL = 'https://github.com/VitalysRDT/rclone-gui-ios';
const ACCENT = '#7C3AED';

const LIMITS = { title: 120, body: 4000, author: 32 };
const KINDS = ['idea', 'bug', 'question'];
const STATUSES = ['new', 'planned', 'in_progress', 'done', 'declined'];

/* ── i18n ──────────────────────────────────────────────────────────── */

const LangContext = React.createContext('en');
const useT = () => {
  const lang = React.useContext(LangContext);
  return (fr, en) => (lang === 'fr' ? fr : (en === undefined ? fr : en));
};

const KIND_LABEL = {
  idea:     { fr: 'Idée',     en: 'Idea' },
  bug:      { fr: 'Bug',      en: 'Bug' },
  question: { fr: 'Question', en: 'Question' },
};
const STATUS_LABEL = {
  new:         { fr: 'Nouveau',   en: 'New' },
  planned:     { fr: 'Prévu',     en: 'Planned' },
  in_progress: { fr: 'En cours',  en: 'In progress' },
  done:        { fr: 'Livré',     en: 'Shipped' },
  declined:    { fr: 'Écarté',    en: 'Declined' },
};
const KIND_PLURAL = {
  idea:     { fr: 'Idées',     en: 'Ideas' },
  bug:      { fr: 'Bugs',      en: 'Bugs' },
  question: { fr: 'Questions', en: 'Questions' },
};
const SORT_LABEL = {
  active: { fr: 'Activité récente', en: 'Recent activity' },
  top:    { fr: 'Les plus votés',   en: 'Most voted' },
  new:    { fr: 'Les plus récents', en: 'Newest' },
};

// Server error codes → something a human can act on.
const ERRORS = {
  invalid_kind:     { fr: 'Choisissez une catégorie.', en: 'Pick a category.' },
  invalid_email:    { fr: 'Cette adresse e-mail semble incorrecte.', en: 'That e-mail address looks wrong.' },
  invalid_topic:    { fr: 'Sujet introuvable.', en: 'Topic not found.' },
  title_too_short:  { fr: 'Le titre est trop court (3 caractères minimum).', en: 'The title is too short (3 characters minimum).' },
  title_too_long:   { fr: 'Le titre est trop long (120 caractères maximum).', en: 'The title is too long (120 characters maximum).' },
  body_too_short:   { fr: 'Le message est trop court — décrivez un peu plus.', en: 'Your message is too short — please add a little detail.' },
  body_too_long:    { fr: 'Le message est trop long (4 000 caractères maximum).', en: 'Your message is too long (4,000 characters maximum).' },
  author_too_short: { fr: 'Votre pseudo est trop court (2 caractères minimum).', en: 'Your name is too short (2 characters minimum).' },
  author_too_long:  { fr: 'Votre pseudo est trop long (32 caractères maximum).', en: 'Your name is too long (32 characters maximum).' },
  spam:             { fr: 'Ce message a été filtré automatiquement. Reformulez-le sans liens ni majuscules excessives.', en: 'This message was caught by the spam filter. Try again without excessive links or capitals.' },
  rate_limited:     { fr: 'Vous publiez trop vite. Réessayez dans une heure.', en: 'You are posting too fast. Try again in an hour.' },
  flood:            { fr: 'Le forum reçoit trop de messages en ce moment. Réessayez plus tard.', en: 'The forum is getting too many posts right now. Please try again later.' },
  topic_locked:     { fr: 'Ce sujet est fermé aux réponses.', en: 'This topic is closed for replies.' },
  not_found:        { fr: 'Introuvable — ce message a peut-être été supprimé.', en: 'Not found — this post may have been deleted.' },
  network:          { fr: 'Connexion impossible. Vérifiez votre réseau et réessayez.', en: 'Could not reach the forum. Check your connection and try again.' },
  server_error:     { fr: 'Une erreur est survenue de notre côté. Réessayez dans un instant.', en: 'Something broke on our side. Please try again in a moment.' },
};

const errorText = (code, lang) => {
  const entry = ERRORS[code] || ERRORS.server_error;
  return lang === 'fr' ? entry.fr : entry.en;
};

/* ── local state that survives a reload ────────────────────────────── */

const store = {
  read(key, fallback) {
    try {
      const raw = window.localStorage.getItem(`rgforum.${key}`);
      return raw ? JSON.parse(raw) : fallback;
    } catch (e) { return fallback; }
  },
  write(key, value) {
    try { window.localStorage.setItem(`rgforum.${key}`, JSON.stringify(value)); } catch (e) {}
  },
};

// Who you are, so the name and e-mail are not retyped for every post.
const loadIdentity = () => store.read('identity', { author: '', email: '' });
const saveIdentity = (identity) => store.write('identity', identity);

// Deletion tokens handed out by the API, keyed "topic:12" / "reply:34".
const loadTokens = () => store.read('tokens', {});
const rememberToken = (target, id, token) => {
  if (!token) return;
  const tokens = loadTokens();
  tokens[`${target}:${id}`] = token;
  store.write('tokens', tokens);
};
const tokenFor = (target, id) => loadTokens()[`${target}:${id}`];

// Locally known votes, so the list can show the pressed state without asking
// the server for every row.
const loadVotes = () => store.read('votes', []);
const setVoted = (id, voted) => {
  const votes = loadVotes().filter((x) => x !== id);
  if (voted) votes.push(id);
  store.write('votes', votes);
};

/* ── API ───────────────────────────────────────────────────────────── */

async function api(route, { method = 'GET', params = {}, body } = {}) {
  const url = new URL(API);
  url.searchParams.set('r', route);
  Object.entries(params).forEach(([k, v]) => {
    if (v !== null && v !== undefined && v !== '') url.searchParams.set(k, v);
  });

  let res;
  try {
    res = await fetch(url, {
      method,
      headers: body ? { 'Content-Type': 'application/json' } : undefined,
      body: body ? JSON.stringify(body) : undefined,
    });
  } catch (e) {
    const err = new Error('network'); err.code = 'network'; throw err;
  }

  const data = await res.json().catch(() => null);
  if (!res.ok) {
    const err = new Error(`forum ${route} failed`);
    err.code = (data && data.error) || 'server_error';
    throw err;
  }
  return data;
}

/* ── formatting ────────────────────────────────────────────────────── */

const UNITS = [
  ['year', 31536000], ['month', 2592000], ['week', 604800],
  ['day', 86400], ['hour', 3600], ['minute', 60],
];

function timeAgo(iso, lang) {
  const then = new Date(iso).getTime();
  if (!then) return '';
  const seconds = Math.round((then - Date.now()) / 1000);
  const abs = Math.abs(seconds);
  if (abs < 45) return lang === 'fr' ? "à l'instant" : 'just now';
  try {
    const rtf = new Intl.RelativeTimeFormat(lang === 'fr' ? 'fr' : 'en', { numeric: 'auto' });
    for (const [unit, secs] of UNITS) {
      if (abs >= secs) return rtf.format(Math.round(seconds / secs), unit);
    }
    return rtf.format(Math.round(seconds), 'second');
  } catch (e) {
    return new Date(iso).toLocaleDateString(lang === 'fr' ? 'fr-FR' : 'en-US');
  }
}

/* ── icons ─────────────────────────────────────────────────────────── */

const Icon = ({ name, size = 16, style }) => {
  const common = {
    width: size, height: size, viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor',
    strokeWidth: 1.9, strokeLinecap: 'round', strokeLinejoin: 'round', style, 'aria-hidden': 'true',
  };
  switch (name) {
    case 'up':       return <svg {...common}><path d="M12 19V5"/><path d="m5 12 7-7 7 7"/></svg>;
    case 'back':     return <svg {...common}><path d="m15 18-6-6 6-6"/></svg>;
    case 'plus':     return <svg {...common}><path d="M12 5v14"/><path d="M5 12h14"/></svg>;
    case 'search':   return <svg {...common}><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>;
    case 'reply':    return <svg {...common}><path d="M21 15a3 3 0 0 1-3 3H8l-5 4V6a3 3 0 0 1 3-3h12a3 3 0 0 1 3 3z"/></svg>;
    case 'idea':     return <svg {...common}><path d="M9 18h6"/><path d="M10 22h4"/><path d="M12 2a6 6 0 0 0-3.6 10.8c.6.5 1 1.3 1.1 2.2h5c.1-.9.5-1.7 1.1-2.2A6 6 0 0 0 12 2Z"/></svg>;
    case 'bug':      return <svg {...common}><path d="M8 2 9.5 4"/><path d="M16 2 14.5 4"/><rect x="7" y="6" width="10" height="14" rx="5"/><path d="M3 10h4M17 10h4M3 16h4M17 16h4M12 8v10"/></svg>;
    case 'question': return <svg {...common}><circle cx="12" cy="12" r="9"/><path d="M9.5 9a2.6 2.6 0 0 1 5 1c0 1.7-2.5 2-2.5 3.5"/><path d="M12 17.5h.01"/></svg>;
    case 'pin':      return <svg {...common}><path d="M12 17v5"/><path d="M9 2h6l-1 6 3 3v2H7v-2l3-3z"/></svg>;
    case 'lock':     return <svg {...common}><rect x="4" y="10" width="16" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/></svg>;
    case 'trash':    return <svg {...common}><path d="M4 7h16"/><path d="M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2"/><path d="M6 7l1 13a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1l1-13"/></svg>;
    case 'check':    return <svg {...common}><path d="m4 12 5 5L20 6"/></svg>;
    default:         return null;
  }
};

const KIND_ICON = { idea: 'idea', bug: 'bug', question: 'question' };

/* ── shared bits ───────────────────────────────────────────────────── */

const Message = ({ kind = 'err', children }) => (
  <div className={`msg ${kind}`} role={kind === 'err' ? 'alert' : 'status'}>{children}</div>
);

const Counter = ({ value, max }) => (
  <span className={`counter${value > max ? ' over' : ''}`}>{value}/{max}</span>
);

const Header = ({ lang, setLang }) => {
  const t = useT();
  return (
    <header className="nav">
      <div className="wrap nav-in">
        <a className="brand" href="index.html"><img src="icon.png" alt="Rclone GUI"/>Rclone GUI</a>
        <div className="nav-sp"/>
        <a className="ghost navlink" href="index.html#versions">{t('Nouveautés', "What's new")}</a>
        <a className="ghost navlink" href="index.html#roadmap">Roadmap</a>
        <a className="ghost navlink" href="index.html#faq">FAQ</a>
        <a className="ghost" href={GITHUB_URL} target="_blank" rel="noopener" style={{ marginRight: 6 }}>GitHub</a>
        <div className="lang">
          <button className={lang === 'en' ? 'on' : ''} onClick={() => setLang('en')}>EN</button>
          <button className={lang === 'fr' ? 'on' : ''} onClick={() => setLang('fr')}>FR</button>
        </div>
      </div>
    </header>
  );
};

const Footer = () => {
  const t = useT();
  return (
    <footer>
      <div className="wrap foot-in">
        <span>© {new Date().getFullYear()} Rclone GUI</span>
        <a href="index.html">{t('Accueil', 'Home')}</a>
        <a href="privacy.html">{t('Confidentialité', 'Privacy')}</a>
        <a href={`${GITHUB_URL}/issues`} target="_blank" rel="noopener">GitHub Issues</a>
        <a href="mailto:vitalys@rougetet.com">vitalys@rougetet.com</a>
      </div>
    </footer>
  );
};

/* ── vote button ───────────────────────────────────────────────────── */

const VoteButton = ({ topic, onVoted }) => {
  const t = useT();
  const [pending, setPending] = React.useState(false);
  const [voted, setVotedState] = React.useState(
    topic.voted !== undefined ? topic.voted : loadVotes().includes(topic.id),
  );
  const [count, setCount] = React.useState(topic.votes || 0);

  React.useEffect(() => {
    setCount(topic.votes || 0);
    if (topic.voted !== undefined) setVotedState(topic.voted);
  }, [topic.id, topic.votes, topic.voted]);

  const toggle = async (e) => {
    e.preventDefault();
    e.stopPropagation();
    if (pending) return;
    setPending(true);
    // Optimistic: the button reacts immediately, and rolls back on failure.
    const nextVoted = !voted;
    setVotedState(nextVoted);
    setCount((c) => c + (nextVoted ? 1 : -1));
    try {
      const res = await api('vote', { method: 'POST', body: { topic_id: topic.id } });
      setVotedState(res.voted);
      setCount(res.votes);
      setVoted(topic.id, res.voted);
      if (onVoted) onVoted(topic.id, res);
    } catch (err) {
      setVotedState(!nextVoted);
      setCount((c) => c + (nextVoted ? -1 : 1));
    } finally {
      setPending(false);
    }
  };

  return (
    <button
      className={`vote${voted ? ' on' : ''}`}
      onClick={toggle}
      aria-pressed={voted}
      aria-label={t('Voter pour ce sujet', 'Vote for this topic')}
      title={voted ? t('Retirer mon vote', 'Remove my vote') : t('Voter', 'Vote')}
    >
      <Icon name="up" size={15}/>
      <b>{count}</b>
      <span>{t('vote', 'vote')}</span>
    </button>
  );
};

/* ── list ──────────────────────────────────────────────────────────── */

const TopicRow = ({ topic, lang, onOpen }) => {
  const t = useT();
  return (
    <a className="topic" href={`#/t/${topic.id}`} onClick={(e) => { e.preventDefault(); onOpen(topic.id); }}>
      <VoteButton topic={topic}/>
      <div className="tmain">
        <div className="tmeta">
          <span className={`tag ${topic.kind}`}>{KIND_LABEL[topic.kind][lang]}</span>
          {topic.status !== 'new' && (
            <span className={`status ${topic.status}`}>{STATUS_LABEL[topic.status][lang]}</span>
          )}
          {topic.pinned && <span className="status"><Icon name="pin" size={11}/> {t('Épinglé', 'Pinned')}</span>}
          {topic.locked && <span className="status"><Icon name="lock" size={11}/> {t('Fermé', 'Closed')}</span>}
        </div>
        <h3 className="ttitle">{topic.title}</h3>
        <p className="texcerpt">{topic.body}</p>
        <div className="tfoot">
          <span>{topic.author}</span>
          <span>{timeAgo(topic.created_at, lang)}</span>
          <span><Icon name="reply" size={13}/>{topic.replies} {topic.replies === 1
            ? t('réponse', 'reply') : t('réponses', 'replies')}</span>
        </div>
      </div>
    </a>
  );
};

const Filters = ({ filters, setFilters, lang }) => {
  const t = useT();
  const [draft, setDraft] = React.useState(filters.q);

  // Debounced search: typing should not fire a request per keystroke.
  React.useEffect(() => {
    const id = setTimeout(() => {
      if (draft !== filters.q) setFilters((f) => ({ ...f, q: draft }));
    }, 350);
    return () => clearTimeout(id);
  }, [draft]);

  return (
    <div className="toolbar">
      <div className="chips">
        <button className={`chip${!filters.kind ? ' on' : ''}`}
          onClick={() => setFilters((f) => ({ ...f, kind: '' }))}>{t('Tout', 'All')}</button>
        {KINDS.map((kind) => (
          <button key={kind} className={`chip${filters.kind === kind ? ' on' : ''}`}
            onClick={() => setFilters((f) => ({ ...f, kind: f.kind === kind ? '' : kind }))}>
            <Icon name={KIND_ICON[kind]} size={13}/>
            {KIND_PLURAL[kind][lang]}
          </button>
        ))}
      </div>
      <div className="search">
        <Icon name="search" size={15}/>
        <input
          type="search"
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          placeholder={t('Rechercher…', 'Search…')}
          aria-label={t('Rechercher dans le forum', 'Search the forum')}
        />
      </div>
      <select className="sortsel" value={filters.sort}
        onChange={(e) => setFilters((f) => ({ ...f, sort: e.target.value }))}
        aria-label={t('Trier', 'Sort')}>
        {Object.keys(SORT_LABEL).map((key) => (
          <option key={key} value={key}>{SORT_LABEL[key][lang]}</option>
        ))}
      </select>
    </div>
  );
};

const StatusFilter = ({ filters, setFilters, lang }) => {
  const t = useT();
  return (
    <div className="chips" style={{ marginTop: 10 }}>
      <button className={`chip${!filters.status ? ' on' : ''}`}
        onClick={() => setFilters((f) => ({ ...f, status: '' }))}>{t('Tous statuts', 'Any status')}</button>
      {STATUSES.map((status) => (
        <button key={status} className={`chip${filters.status === status ? ' on' : ''}`}
          onClick={() => setFilters((f) => ({ ...f, status: f.status === status ? '' : status }))}>
          {STATUS_LABEL[status][lang]}
        </button>
      ))}
    </div>
  );
};

const Stats = ({ stats, lang }) => {
  const t = useT();
  if (!stats) return null;
  const cells = [
    [stats.topics, t('sujets', 'topics')],
    [stats.ideas, t('idées', 'ideas')],
    [stats.bugs, t('bugs', 'bugs')],
    [stats.done, t('livrés', 'shipped')],
  ];
  return (
    <div className="stats">
      {cells.map(([n, label]) => (
        <div className="stat" key={label}><b>{n}</b><span>{label}</span></div>
      ))}
    </div>
  );
};

/* ── forms ─────────────────────────────────────────────────────────── */

// Name + optional e-mail, shared by both forms and remembered locally.
const IdentityFields = ({ identity, setIdentity }) => {
  const t = useT();
  return (
    <div className="row2">
      <div className="field">
        <label htmlFor="author">{t('Votre pseudo', 'Your name')}</label>
        <input id="author" value={identity.author} maxLength={LIMITS.author}
          onChange={(e) => setIdentity({ ...identity, author: e.target.value })}
          placeholder={t('Camille', 'Camille')} autoComplete="nickname"/>
      </div>
      <div className="field">
        <label htmlFor="email">{t('E-mail (facultatif)', 'E-mail (optional)')}</label>
        <input id="email" type="email" value={identity.email}
          onChange={(e) => setIdentity({ ...identity, email: e.target.value })}
          placeholder={t('pour être prévenu', 'to get a reply')} autoComplete="email"/>
        <p className="hint">{t(
          'Jamais affiché publiquement. Sert uniquement à vous répondre.',
          'Never shown publicly. Only used to get back to you.',
        )}</p>
      </div>
    </div>
  );
};

const NewTopicForm = ({ lang, onCreated, onCancel }) => {
  const t = useT();
  const [kind, setKind] = React.useState('idea');
  const [title, setTitle] = React.useState('');
  const [body, setBody] = React.useState('');
  const [identity, setIdentity] = React.useState(loadIdentity);
  const [website, setWebsite] = React.useState('');   // honeypot
  const [error, setError] = React.useState(null);
  const [sending, setSending] = React.useState(false);

  const submit = async (e) => {
    e.preventDefault();
    if (sending) return;
    setError(null);
    setSending(true);
    try {
      const topic = await api('topic', {
        method: 'POST',
        body: {
          kind,
          title,
          body,
          author: identity.author,
          email: identity.email,
          lang,
          website,
        },
      });
      saveIdentity(identity);
      rememberToken('topic', topic.id, topic.token);
      onCreated(topic);
    } catch (err) {
      setError(err.code || 'server_error');
    } finally {
      setSending(false);
    }
  };

  return (
    <form className="form" onSubmit={submit}>
      <h3>{t('Nouveau sujet', 'New topic')}</h3>

      <div className="field">
        <label>{t('Catégorie', 'Category')}</label>
        <div className="kinds">
          {KINDS.map((k) => (
            <button type="button" key={k} className={`kindbtn${kind === k ? ' on' : ''}`}
              onClick={() => setKind(k)} aria-pressed={kind === k}>
              <Icon name={KIND_ICON[k]} size={19}/>
              {KIND_LABEL[k][lang]}
            </button>
          ))}
        </div>
      </div>

      <div className="field">
        <label htmlFor="title">
          {t('Titre', 'Title')}
          <Counter value={title.length} max={LIMITS.title}/>
        </label>
        <input id="title" value={title} maxLength={LIMITS.title} required
          onChange={(e) => setTitle(e.target.value)}
          placeholder={kind === 'bug'
            ? t('Le lecteur vidéo se fige sur les fichiers MKV', 'Video player freezes on MKV files')
            : t('Pouvoir trier les fichiers par taille', 'Let me sort files by size')}/>
      </div>

      <div className="field">
        <label htmlFor="body">
          {t('Description', 'Description')}
          <Counter value={body.length} max={LIMITS.body}/>
        </label>
        <textarea id="body" value={body} maxLength={LIMITS.body} required
          onChange={(e) => setBody(e.target.value)}
          placeholder={kind === 'bug'
            ? t('Ce qui se passe, ce que vous attendiez, votre appareil et la version de l\'app.',
                'What happens, what you expected, your device and the app version.')
            : t('Décrivez votre idée et ce qu\'elle vous permettrait de faire.',
                'Describe your idea and what it would let you do.')}/>
        <p className="hint">{t(
          'Pour un bug, précisez votre appareil, la version d\'iOS et celle de l\'app — cela fait gagner un aller-retour.',
          'For a bug, mention your device, your iOS version and the app version — it saves a round trip.',
        )}</p>
      </div>

      <IdentityFields identity={identity} setIdentity={setIdentity}/>

      <div className="honey" aria-hidden="true">
        <label htmlFor="website">Website</label>
        <input id="website" tabIndex="-1" autoComplete="off"
          value={website} onChange={(e) => setWebsite(e.target.value)}/>
      </div>

      {error && <Message>{errorText(error, lang)}</Message>}

      <div className="actions">
        <button className="btn btn-violet" type="submit" disabled={sending}>
          {sending ? t('Publication…', 'Posting…') : t('Publier', 'Post')}
        </button>
        <button className="btn btn-plain" type="button" onClick={onCancel}>
          {t('Annuler', 'Cancel')}
        </button>
        <span className="hint" style={{ margin: 0 }}>{t(
          'Publié immédiatement et visible publiquement.',
          'Posted immediately and publicly visible.',
        )}</span>
      </div>
    </form>
  );
};

const ReplyForm = ({ topicId, lang, onReplied }) => {
  const t = useT();
  const [body, setBody] = React.useState('');
  const [identity, setIdentity] = React.useState(loadIdentity);
  const [website, setWebsite] = React.useState('');
  const [error, setError] = React.useState(null);
  const [sending, setSending] = React.useState(false);

  const submit = async (e) => {
    e.preventDefault();
    if (sending) return;
    setError(null);
    setSending(true);
    try {
      const reply = await api('reply', {
        method: 'POST',
        body: { topic_id: topicId, body, author: identity.author, email: identity.email, website },
      });
      saveIdentity(identity);
      rememberToken('reply', reply.id, reply.token);
      setBody('');
      onReplied(reply);
    } catch (err) {
      setError(err.code || 'server_error');
    } finally {
      setSending(false);
    }
  };

  return (
    <form className="form" onSubmit={submit}>
      <h3>{t('Répondre', 'Reply')}</h3>
      <div className="field">
        <label htmlFor="reply-body">
          {t('Votre message', 'Your message')}
          <Counter value={body.length} max={LIMITS.body}/>
        </label>
        <textarea id="reply-body" value={body} maxLength={LIMITS.body} required
          onChange={(e) => setBody(e.target.value)}
          placeholder={t('Ajoutez votre expérience, un détail utile…', 'Add your own experience, a useful detail…')}
          style={{ minHeight: 100 }}/>
      </div>

      <IdentityFields identity={identity} setIdentity={setIdentity}/>

      <div className="honey" aria-hidden="true">
        <label htmlFor="reply-website">Website</label>
        <input id="reply-website" tabIndex="-1" autoComplete="off"
          value={website} onChange={(e) => setWebsite(e.target.value)}/>
      </div>

      {error && <Message>{errorText(error, lang)}</Message>}

      <div className="actions">
        <button className="btn btn-violet" type="submit" disabled={sending}>
          {sending ? t('Envoi…', 'Sending…') : t('Envoyer', 'Send')}
        </button>
      </div>
    </form>
  );
};

/* ── detail view ───────────────────────────────────────────────────── */

const DeleteOwn = ({ target, id, lang, onDeleted }) => {
  const t = useT();
  const token = tokenFor(target, id);
  const [confirming, setConfirming] = React.useState(false);
  const [error, setError] = React.useState(null);
  if (!token) return null;

  const remove = async () => {
    setError(null);
    try {
      await api('own', { method: 'DELETE', params: { target, id, token } });
      onDeleted();
    } catch (err) {
      setError(err.code || 'server_error');
    }
  };

  if (error) return <span className="hint" style={{ color: '#a3231a' }}>{errorText(error, lang)}</span>;

  return confirming ? (
    <span style={{ display: 'inline-flex', gap: 10, alignItems: 'center' }}>
      <button className="linkish" style={{ color: '#a3231a' }} onClick={remove}>
        {t('Confirmer la suppression', 'Confirm deletion')}
      </button>
      <button className="linkish" onClick={() => setConfirming(false)}>{t('Annuler', 'Cancel')}</button>
    </span>
  ) : (
    <button className="linkish" onClick={() => setConfirming(true)}>
      <Icon name="trash" size={12}/> {t('Supprimer', 'Delete')}
    </button>
  );
};

const TopicDetail = ({ id, lang, onBack, onDeleted }) => {
  const t = useT();
  const [topic, setTopic] = React.useState(null);
  const [error, setError] = React.useState(null);

  const load = React.useCallback(async () => {
    setError(null);
    try {
      setTopic(await api('topic', { params: { id } }));
    } catch (err) {
      setError(err.code || 'server_error');
    }
  }, [id]);

  React.useEffect(() => { load(); }, [load]);

  if (error) {
    return (
      <div className="wrap">
        <button className="back" onClick={onBack}><Icon name="back" size={15}/>{t('Retour', 'Back')}</button>
        <Message>{errorText(error, lang)}</Message>
      </div>
    );
  }
  if (!topic) {
    return (
      <div className="wrap">
        <button className="back" onClick={onBack}><Icon name="back" size={15}/>{t('Retour', 'Back')}</button>
        <div className="skeleton" style={{ height: 200, marginTop: 14 }}/>
      </div>
    );
  }

  return (
    <div className="wrap">
      <button className="back" onClick={onBack}>
        <Icon name="back" size={15}/>{t('Tous les sujets', 'All topics')}
      </button>

      <article className="detail">
        <div className="tmeta">
          <span className={`tag ${topic.kind}`}>{KIND_LABEL[topic.kind][lang]}</span>
          <span className={`status ${topic.status}`}>{STATUS_LABEL[topic.status][lang]}</span>
          {topic.pinned && <span className="status"><Icon name="pin" size={11}/> {t('Épinglé', 'Pinned')}</span>}
          {topic.locked && <span className="status"><Icon name="lock" size={11}/> {t('Fermé', 'Closed')}</span>}
        </div>

        <h2>{topic.title}</h2>

        <div className="byline">
          <span>{topic.author}</span>
          <span>{timeAgo(topic.created_at, lang)}</span>
          <DeleteOwn target="topic" id={topic.id} lang={lang} onDeleted={onDeleted}/>
        </div>

        <p className="prose">{topic.body}</p>

        {topic.official_reply && (
          <div className="official">
            <div className="lab"><Icon name="check" size={12}/> {t('Réponse du développeur', 'Developer reply')}</div>
            <p>{topic.official_reply}</p>
          </div>
        )}

        <div style={{ marginTop: 20 }}>
          <VoteButton topic={topic} onVoted={(_, res) => setTopic((prev) => ({ ...prev, ...res }))}/>
        </div>
      </article>

      <h3 style={{ margin: '28px 0 0', fontSize: 17, letterSpacing: '-.3px' }}>
        {topic.replies_list.length === 0
          ? t('Aucune réponse pour le moment', 'No replies yet')
          : `${topic.replies_list.length} ${topic.replies_list.length === 1
            ? t('réponse', 'reply') : t('réponses', 'replies')}`}
      </h3>

      <div className="replies">
        {topic.replies_list.map((reply) => (
          <div className={`reply${reply.staff ? ' staff' : ''}`} key={reply.id}>
            <div className="rhead">
              <span className="who">{reply.author}</span>
              {reply.staff && <span className="devtag">{t('Développeur', 'Developer')}</span>}
              <span className="when">{timeAgo(reply.created_at, lang)}</span>
              <DeleteOwn target="reply" id={reply.id} lang={lang} onDeleted={load}/>
            </div>
            <p className="rbody">{reply.body}</p>
          </div>
        ))}
      </div>

      {topic.locked
        ? <div className="empty" style={{ marginTop: 20 }}>
            <Icon name="lock" size={15}/> {t('Ce sujet est fermé aux nouvelles réponses.', 'This topic is closed for new replies.')}
          </div>
        : <ReplyForm topicId={topic.id} lang={lang} onReplied={load}/>}
    </div>
  );
};

/* ── list view ─────────────────────────────────────────────────────── */

const PAGE = 20;

const TopicList = ({ lang, onOpen }) => {
  const t = useT();
  const [filters, setFilters] = React.useState({ kind: '', status: '', sort: 'active', q: '' });
  const [state, setState] = React.useState({ items: [], total: 0, loading: true, error: null });
  const [offset, setOffset] = React.useState(0);
  const [stats, setStats] = React.useState(null);
  const [composing, setComposing] = React.useState(false);
  const [posted, setPosted] = React.useState(false);

  React.useEffect(() => { setOffset(0); }, [filters.kind, filters.status, filters.sort, filters.q]);

  React.useEffect(() => {
    let cancelled = false;
    setState((s) => ({ ...s, loading: true, error: null }));
    api('topics', { params: { ...filters, limit: PAGE, offset } })
      .then((data) => {
        if (cancelled) return;
        setState((s) => ({
          items: offset === 0 ? data.items : [...s.items, ...data.items],
          total: data.total,
          loading: false,
          error: null,
        }));
      })
      .catch((err) => {
        if (!cancelled) setState((s) => ({ ...s, loading: false, error: err.code || 'server_error' }));
      });
    return () => { cancelled = true; };
  }, [filters.kind, filters.status, filters.sort, filters.q, offset]);

  const loadStats = React.useCallback(() => {
    api('stats').then(setStats).catch(() => setStats(null));
  }, []);
  React.useEffect(() => { loadStats(); }, [loadStats]);

  const onCreated = (topic) => {
    setComposing(false);
    setPosted(true);
    loadStats();
    onOpen(topic.id);
  };

  const { items, total, loading, error } = state;
  const hasMore = items.length < total;

  return (
    <React.Fragment>
      <div className="fhead">
        <div className="wrap">
          <p className="eyebrow">{t('Forum public', 'Public forum')}</p>
          <h1 className="ftitle">{t('Vos idées font l\'app', 'Your ideas shape the app')}</h1>
          <p className="fsub">{t(
            'Proposez une idée, signalez un bug, posez une question. Votez pour ce qui compte pour vous — sans créer de compte.',
            'Suggest an idea, report a bug, ask a question. Vote for what matters to you — no account needed.',
          )}</p>
          <Stats stats={stats} lang={lang}/>
          {!composing && (
            <div className="center">
              <button className="btn btn-violet" onClick={() => { setPosted(false); setComposing(true); }}>
                <Icon name="plus" size={17}/>{t('Nouveau sujet', 'New topic')}
              </button>
            </div>
          )}
        </div>
      </div>

      <div className="wrap">
        {composing && (
          <NewTopicForm lang={lang} onCreated={onCreated} onCancel={() => setComposing(false)}/>
        )}
        {posted && !composing && (
          <Message kind="ok">{t('Merci ! Votre message est en ligne.', 'Thanks! Your post is live.')}</Message>
        )}

        <Filters filters={filters} setFilters={setFilters} lang={lang}/>
        <StatusFilter filters={filters} setFilters={setFilters} lang={lang}/>

        {error && <Message>{errorText(error, lang)}</Message>}

        {loading && offset === 0 && !error && (
          <div className="list">
            {[0, 1, 2, 3].map((i) => <div className="skeleton" key={i}/>)}
          </div>
        )}

        {!loading && !error && items.length === 0 && (
          <div className="empty">
            {filters.q || filters.kind || filters.status
              ? t('Aucun sujet ne correspond à ce filtre.', 'No topic matches these filters.')
              : t('Rien ici pour l\'instant — lancez la première discussion !', 'Nothing here yet — start the first discussion!')}
          </div>
        )}

        {items.length > 0 && (
          <div className="list">
            {items.map((topic) => (
              <TopicRow key={topic.id} topic={topic} lang={lang} onOpen={onOpen}/>
            ))}
          </div>
        )}

        {hasMore && !error && (
          <div className="center">
            <button className="btn btn-plain" disabled={loading}
              onClick={() => setOffset(items.length)}>
              {loading ? t('Chargement…', 'Loading…') : t('Voir plus de sujets', 'Show more topics')}
            </button>
          </div>
        )}
      </div>
    </React.Fragment>
  );
};

/* ── app shell + hash routing ──────────────────────────────────────── */

const topicIdFromHash = () => {
  const match = /^#\/t\/(\d+)$/.exec(window.location.hash || '');
  return match ? Number(match[1]) : null;
};

const detectLang = () => {
  const saved = store.read('lang', null);
  if (saved === 'fr' || saved === 'en') return saved;
  return (navigator.language || 'en').toLowerCase().startsWith('fr') ? 'fr' : 'en';
};

const App = () => {
  const [lang, setLangState] = React.useState(detectLang);
  const [topicId, setTopicId] = React.useState(topicIdFromHash);

  React.useEffect(() => {
    const onHash = () => setTopicId(topicIdFromHash());
    window.addEventListener('hashchange', onHash);
    return () => window.removeEventListener('hashchange', onHash);
  }, []);

  React.useEffect(() => {
    document.documentElement.lang = lang;
  }, [lang]);

  const setLang = (next) => {
    setLangState(next);
    store.write('lang', next);
  };

  const openTopic = (id) => {
    window.location.hash = `#/t/${id}`;
    setTopicId(id);
    window.scrollTo({ top: 0, behavior: 'smooth' });
  };

  const backToList = () => {
    window.location.hash = '';
    setTopicId(null);
  };

  return (
    <LangContext.Provider value={lang}>
      <Header lang={lang} setLang={setLang}/>
      {topicId
        ? <TopicDetail id={topicId} lang={lang} onBack={backToList} onDeleted={backToList}/>
        : <TopicList lang={lang} onOpen={openTopic}/>}
      <Footer/>
    </LangContext.Provider>
  );
};

ReactDOM.createRoot(document.getElementById('root')).render(<App/>);
