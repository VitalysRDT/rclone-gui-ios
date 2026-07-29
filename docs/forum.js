(() => {
  // docs/forum.src.jsx
  var API = "https://rclone-gui-trial.vercel.app/api/forum";
  var GITHUB_URL = "https://github.com/VitalysRDT/rclone-gui-ios";
  var LIMITS = { title: 120, body: 4e3, author: 32 };
  var KINDS = ["idea", "bug", "question"];
  var STATUSES = ["new", "planned", "in_progress", "done", "declined"];
  var LangContext = React.createContext("en");
  var useT = () => {
    const lang = React.useContext(LangContext);
    return (fr, en) => lang === "fr" ? fr : en === void 0 ? fr : en;
  };
  var KIND_LABEL = {
    idea: { fr: "Id\xE9e", en: "Idea" },
    bug: { fr: "Bug", en: "Bug" },
    question: { fr: "Question", en: "Question" }
  };
  var STATUS_LABEL = {
    new: { fr: "Nouveau", en: "New" },
    planned: { fr: "Pr\xE9vu", en: "Planned" },
    in_progress: { fr: "En cours", en: "In progress" },
    done: { fr: "Livr\xE9", en: "Shipped" },
    declined: { fr: "\xC9cart\xE9", en: "Declined" }
  };
  var KIND_PLURAL = {
    idea: { fr: "Id\xE9es", en: "Ideas" },
    bug: { fr: "Bugs", en: "Bugs" },
    question: { fr: "Questions", en: "Questions" }
  };
  var SORT_LABEL = {
    active: { fr: "Activit\xE9 r\xE9cente", en: "Recent activity" },
    top: { fr: "Les plus vot\xE9s", en: "Most voted" },
    new: { fr: "Les plus r\xE9cents", en: "Newest" }
  };
  var ERRORS = {
    invalid_kind: { fr: "Choisissez une cat\xE9gorie.", en: "Pick a category." },
    invalid_email: { fr: "Cette adresse e-mail semble incorrecte.", en: "That e-mail address looks wrong." },
    invalid_topic: { fr: "Sujet introuvable.", en: "Topic not found." },
    title_too_short: { fr: "Le titre est trop court (3 caract\xE8res minimum).", en: "The title is too short (3 characters minimum)." },
    title_too_long: { fr: "Le titre est trop long (120 caract\xE8res maximum).", en: "The title is too long (120 characters maximum)." },
    body_too_short: { fr: "Le message est trop court \u2014 d\xE9crivez un peu plus.", en: "Your message is too short \u2014 please add a little detail." },
    body_too_long: { fr: "Le message est trop long (4 000 caract\xE8res maximum).", en: "Your message is too long (4,000 characters maximum)." },
    author_too_short: { fr: "Votre pseudo est trop court (2 caract\xE8res minimum).", en: "Your name is too short (2 characters minimum)." },
    author_too_long: { fr: "Votre pseudo est trop long (32 caract\xE8res maximum).", en: "Your name is too long (32 characters maximum)." },
    spam: { fr: "Ce message a \xE9t\xE9 filtr\xE9 automatiquement. Reformulez-le sans liens ni majuscules excessives.", en: "This message was caught by the spam filter. Try again without excessive links or capitals." },
    rate_limited: { fr: "Vous publiez trop vite. R\xE9essayez dans une heure.", en: "You are posting too fast. Try again in an hour." },
    flood: { fr: "Le forum re\xE7oit trop de messages en ce moment. R\xE9essayez plus tard.", en: "The forum is getting too many posts right now. Please try again later." },
    topic_locked: { fr: "Ce sujet est ferm\xE9 aux r\xE9ponses.", en: "This topic is closed for replies." },
    not_found: { fr: "Introuvable \u2014 ce message a peut-\xEAtre \xE9t\xE9 supprim\xE9.", en: "Not found \u2014 this post may have been deleted." },
    network: { fr: "Connexion impossible. V\xE9rifiez votre r\xE9seau et r\xE9essayez.", en: "Could not reach the forum. Check your connection and try again." },
    server_error: { fr: "Une erreur est survenue de notre c\xF4t\xE9. R\xE9essayez dans un instant.", en: "Something broke on our side. Please try again in a moment." }
  };
  var errorText = (code, lang) => {
    const entry = ERRORS[code] || ERRORS.server_error;
    return lang === "fr" ? entry.fr : entry.en;
  };
  var store = {
    read(key, fallback) {
      try {
        const raw = window.localStorage.getItem(`rgforum.${key}`);
        return raw ? JSON.parse(raw) : fallback;
      } catch (e) {
        return fallback;
      }
    },
    write(key, value) {
      try {
        window.localStorage.setItem(`rgforum.${key}`, JSON.stringify(value));
      } catch (e) {
      }
    }
  };
  var loadIdentity = () => store.read("identity", { author: "", email: "" });
  var saveIdentity = (identity) => store.write("identity", identity);
  var loadTokens = () => store.read("tokens", {});
  var rememberToken = (target, id, token) => {
    if (!token) return;
    const tokens = loadTokens();
    tokens[`${target}:${id}`] = token;
    store.write("tokens", tokens);
  };
  var tokenFor = (target, id) => loadTokens()[`${target}:${id}`];
  var loadVotes = () => store.read("votes", []);
  var setVoted = (id, voted) => {
    const votes = loadVotes().filter((x) => x !== id);
    if (voted) votes.push(id);
    store.write("votes", votes);
  };
  async function api(route, { method = "GET", params = {}, body } = {}) {
    const url = new URL(API);
    url.searchParams.set("r", route);
    Object.entries(params).forEach(([k, v]) => {
      if (v !== null && v !== void 0 && v !== "") url.searchParams.set(k, v);
    });
    let res;
    try {
      res = await fetch(url, {
        method,
        headers: body ? { "Content-Type": "application/json" } : void 0,
        body: body ? JSON.stringify(body) : void 0
      });
    } catch (e) {
      const err = new Error("network");
      err.code = "network";
      throw err;
    }
    const data = await res.json().catch(() => null);
    if (!res.ok) {
      const err = new Error(`forum ${route} failed`);
      err.code = data && data.error || "server_error";
      throw err;
    }
    return data;
  }
  var UNITS = [
    ["year", 31536e3],
    ["month", 2592e3],
    ["week", 604800],
    ["day", 86400],
    ["hour", 3600],
    ["minute", 60]
  ];
  function timeAgo(iso, lang) {
    const then = new Date(iso).getTime();
    if (!then) return "";
    const seconds = Math.round((then - Date.now()) / 1e3);
    const abs = Math.abs(seconds);
    if (abs < 45) return lang === "fr" ? "\xE0 l'instant" : "just now";
    try {
      const rtf = new Intl.RelativeTimeFormat(lang === "fr" ? "fr" : "en", { numeric: "auto" });
      for (const [unit, secs] of UNITS) {
        if (abs >= secs) return rtf.format(Math.round(seconds / secs), unit);
      }
      return rtf.format(Math.round(seconds), "second");
    } catch (e) {
      return new Date(iso).toLocaleDateString(lang === "fr" ? "fr-FR" : "en-US");
    }
  }
  var Icon = ({ name, size = 16, style }) => {
    const common = {
      width: size,
      height: size,
      viewBox: "0 0 24 24",
      fill: "none",
      stroke: "currentColor",
      strokeWidth: 1.9,
      strokeLinecap: "round",
      strokeLinejoin: "round",
      style,
      "aria-hidden": "true"
    };
    switch (name) {
      case "up":
        return /* @__PURE__ */ React.createElement("svg", { ...common }, /* @__PURE__ */ React.createElement("path", { d: "M12 19V5" }), /* @__PURE__ */ React.createElement("path", { d: "m5 12 7-7 7 7" }));
      case "back":
        return /* @__PURE__ */ React.createElement("svg", { ...common }, /* @__PURE__ */ React.createElement("path", { d: "m15 18-6-6 6-6" }));
      case "plus":
        return /* @__PURE__ */ React.createElement("svg", { ...common }, /* @__PURE__ */ React.createElement("path", { d: "M12 5v14" }), /* @__PURE__ */ React.createElement("path", { d: "M5 12h14" }));
      case "search":
        return /* @__PURE__ */ React.createElement("svg", { ...common }, /* @__PURE__ */ React.createElement("circle", { cx: "11", cy: "11", r: "7" }), /* @__PURE__ */ React.createElement("path", { d: "m20 20-3.5-3.5" }));
      case "reply":
        return /* @__PURE__ */ React.createElement("svg", { ...common }, /* @__PURE__ */ React.createElement("path", { d: "M21 15a3 3 0 0 1-3 3H8l-5 4V6a3 3 0 0 1 3-3h12a3 3 0 0 1 3 3z" }));
      case "idea":
        return /* @__PURE__ */ React.createElement("svg", { ...common }, /* @__PURE__ */ React.createElement("path", { d: "M9 18h6" }), /* @__PURE__ */ React.createElement("path", { d: "M10 22h4" }), /* @__PURE__ */ React.createElement("path", { d: "M12 2a6 6 0 0 0-3.6 10.8c.6.5 1 1.3 1.1 2.2h5c.1-.9.5-1.7 1.1-2.2A6 6 0 0 0 12 2Z" }));
      case "bug":
        return /* @__PURE__ */ React.createElement("svg", { ...common }, /* @__PURE__ */ React.createElement("path", { d: "M8 2 9.5 4" }), /* @__PURE__ */ React.createElement("path", { d: "M16 2 14.5 4" }), /* @__PURE__ */ React.createElement("rect", { x: "7", y: "6", width: "10", height: "14", rx: "5" }), /* @__PURE__ */ React.createElement("path", { d: "M3 10h4M17 10h4M3 16h4M17 16h4M12 8v10" }));
      case "question":
        return /* @__PURE__ */ React.createElement("svg", { ...common }, /* @__PURE__ */ React.createElement("circle", { cx: "12", cy: "12", r: "9" }), /* @__PURE__ */ React.createElement("path", { d: "M9.5 9a2.6 2.6 0 0 1 5 1c0 1.7-2.5 2-2.5 3.5" }), /* @__PURE__ */ React.createElement("path", { d: "M12 17.5h.01" }));
      case "pin":
        return /* @__PURE__ */ React.createElement("svg", { ...common }, /* @__PURE__ */ React.createElement("path", { d: "M12 17v5" }), /* @__PURE__ */ React.createElement("path", { d: "M9 2h6l-1 6 3 3v2H7v-2l3-3z" }));
      case "lock":
        return /* @__PURE__ */ React.createElement("svg", { ...common }, /* @__PURE__ */ React.createElement("rect", { x: "4", y: "10", width: "16", height: "11", rx: "2" }), /* @__PURE__ */ React.createElement("path", { d: "M8 10V7a4 4 0 0 1 8 0v3" }));
      case "trash":
        return /* @__PURE__ */ React.createElement("svg", { ...common }, /* @__PURE__ */ React.createElement("path", { d: "M4 7h16" }), /* @__PURE__ */ React.createElement("path", { d: "M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2" }), /* @__PURE__ */ React.createElement("path", { d: "M6 7l1 13a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1l1-13" }));
      case "check":
        return /* @__PURE__ */ React.createElement("svg", { ...common }, /* @__PURE__ */ React.createElement("path", { d: "m4 12 5 5L20 6" }));
      default:
        return null;
    }
  };
  var KIND_ICON = { idea: "idea", bug: "bug", question: "question" };
  var Message = ({ kind = "err", children }) => /* @__PURE__ */ React.createElement("div", { className: `msg ${kind}`, role: kind === "err" ? "alert" : "status" }, children);
  var Counter = ({ value, max }) => /* @__PURE__ */ React.createElement("span", { className: `counter${value > max ? " over" : ""}` }, value, "/", max);
  var Header = ({ lang, setLang }) => {
    const t = useT();
    return /* @__PURE__ */ React.createElement("header", { className: "nav" }, /* @__PURE__ */ React.createElement("div", { className: "wrap nav-in" }, /* @__PURE__ */ React.createElement("a", { className: "brand", href: "index.html" }, /* @__PURE__ */ React.createElement("img", { src: "icon.png", alt: "Rclone GUI" }), "Rclone GUI"), /* @__PURE__ */ React.createElement("div", { className: "nav-sp" }), /* @__PURE__ */ React.createElement("a", { className: "ghost navlink", href: "index.html#versions" }, t("Nouveaut\xE9s", "What's new")), /* @__PURE__ */ React.createElement("a", { className: "ghost navlink", href: "index.html#roadmap" }, "Roadmap"), /* @__PURE__ */ React.createElement("a", { className: "ghost navlink", href: "index.html#faq" }, "FAQ"), /* @__PURE__ */ React.createElement("a", { className: "ghost", href: GITHUB_URL, target: "_blank", rel: "noopener", style: { marginRight: 6 } }, "GitHub"), /* @__PURE__ */ React.createElement("div", { className: "lang" }, /* @__PURE__ */ React.createElement("button", { className: lang === "en" ? "on" : "", onClick: () => setLang("en") }, "EN"), /* @__PURE__ */ React.createElement("button", { className: lang === "fr" ? "on" : "", onClick: () => setLang("fr") }, "FR"))));
  };
  var Footer = () => {
    const t = useT();
    return /* @__PURE__ */ React.createElement("footer", null, /* @__PURE__ */ React.createElement("div", { className: "wrap foot-in" }, /* @__PURE__ */ React.createElement("span", null, "\xA9 ", (/* @__PURE__ */ new Date()).getFullYear(), " Rclone GUI"), /* @__PURE__ */ React.createElement("a", { href: "index.html" }, t("Accueil", "Home")), /* @__PURE__ */ React.createElement("a", { href: "privacy.html" }, t("Confidentialit\xE9", "Privacy")), /* @__PURE__ */ React.createElement("a", { href: `${GITHUB_URL}/issues`, target: "_blank", rel: "noopener" }, "GitHub Issues"), /* @__PURE__ */ React.createElement("a", { href: "mailto:vitalys@rougetet.com" }, "vitalys@rougetet.com")));
  };
  var VoteButton = ({ topic, onVoted }) => {
    const t = useT();
    const [pending, setPending] = React.useState(false);
    const [voted, setVotedState] = React.useState(
      topic.voted !== void 0 ? topic.voted : loadVotes().includes(topic.id)
    );
    const [count, setCount] = React.useState(topic.votes || 0);
    React.useEffect(() => {
      setCount(topic.votes || 0);
      if (topic.voted !== void 0) setVotedState(topic.voted);
    }, [topic.id, topic.votes, topic.voted]);
    const toggle = async (e) => {
      e.preventDefault();
      e.stopPropagation();
      if (pending) return;
      setPending(true);
      const nextVoted = !voted;
      setVotedState(nextVoted);
      setCount((c) => c + (nextVoted ? 1 : -1));
      try {
        const res = await api("vote", { method: "POST", body: { topic_id: topic.id } });
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
    return /* @__PURE__ */ React.createElement(
      "button",
      {
        className: `vote${voted ? " on" : ""}`,
        onClick: toggle,
        "aria-pressed": voted,
        "aria-label": t("Voter pour ce sujet", "Vote for this topic"),
        title: voted ? t("Retirer mon vote", "Remove my vote") : t("Voter", "Vote")
      },
      /* @__PURE__ */ React.createElement(Icon, { name: "up", size: 15 }),
      /* @__PURE__ */ React.createElement("b", null, count),
      /* @__PURE__ */ React.createElement("span", null, t("vote", "vote"))
    );
  };
  var TopicRow = ({ topic, lang, onOpen }) => {
    const t = useT();
    return /* @__PURE__ */ React.createElement("a", { className: "topic", href: `#/t/${topic.id}`, onClick: (e) => {
      e.preventDefault();
      onOpen(topic.id);
    } }, /* @__PURE__ */ React.createElement(VoteButton, { topic }), /* @__PURE__ */ React.createElement("div", { className: "tmain" }, /* @__PURE__ */ React.createElement("div", { className: "tmeta" }, /* @__PURE__ */ React.createElement("span", { className: `tag ${topic.kind}` }, KIND_LABEL[topic.kind][lang]), topic.status !== "new" && /* @__PURE__ */ React.createElement("span", { className: `status ${topic.status}` }, STATUS_LABEL[topic.status][lang]), topic.pinned && /* @__PURE__ */ React.createElement("span", { className: "status" }, /* @__PURE__ */ React.createElement(Icon, { name: "pin", size: 11 }), " ", t("\xC9pingl\xE9", "Pinned")), topic.locked && /* @__PURE__ */ React.createElement("span", { className: "status" }, /* @__PURE__ */ React.createElement(Icon, { name: "lock", size: 11 }), " ", t("Ferm\xE9", "Closed"))), /* @__PURE__ */ React.createElement("h3", { className: "ttitle" }, topic.title), /* @__PURE__ */ React.createElement("p", { className: "texcerpt" }, topic.body), /* @__PURE__ */ React.createElement("div", { className: "tfoot" }, /* @__PURE__ */ React.createElement("span", null, topic.author), /* @__PURE__ */ React.createElement("span", null, timeAgo(topic.created_at, lang)), /* @__PURE__ */ React.createElement("span", null, /* @__PURE__ */ React.createElement(Icon, { name: "reply", size: 13 }), topic.replies, " ", topic.replies === 1 ? t("r\xE9ponse", "reply") : t("r\xE9ponses", "replies")))));
  };
  var Filters = ({ filters, setFilters, lang }) => {
    const t = useT();
    const [draft, setDraft] = React.useState(filters.q);
    React.useEffect(() => {
      const id = setTimeout(() => {
        if (draft !== filters.q) setFilters((f) => ({ ...f, q: draft }));
      }, 350);
      return () => clearTimeout(id);
    }, [draft]);
    return /* @__PURE__ */ React.createElement("div", { className: "toolbar" }, /* @__PURE__ */ React.createElement("div", { className: "chips" }, /* @__PURE__ */ React.createElement(
      "button",
      {
        className: `chip${!filters.kind ? " on" : ""}`,
        onClick: () => setFilters((f) => ({ ...f, kind: "" }))
      },
      t("Tout", "All")
    ), KINDS.map((kind) => /* @__PURE__ */ React.createElement(
      "button",
      {
        key: kind,
        className: `chip${filters.kind === kind ? " on" : ""}`,
        onClick: () => setFilters((f) => ({ ...f, kind: f.kind === kind ? "" : kind }))
      },
      /* @__PURE__ */ React.createElement(Icon, { name: KIND_ICON[kind], size: 13 }),
      KIND_PLURAL[kind][lang]
    ))), /* @__PURE__ */ React.createElement("div", { className: "search" }, /* @__PURE__ */ React.createElement(Icon, { name: "search", size: 15 }), /* @__PURE__ */ React.createElement(
      "input",
      {
        type: "search",
        value: draft,
        onChange: (e) => setDraft(e.target.value),
        placeholder: t("Rechercher\u2026", "Search\u2026"),
        "aria-label": t("Rechercher dans le forum", "Search the forum")
      }
    )), /* @__PURE__ */ React.createElement(
      "select",
      {
        className: "sortsel",
        value: filters.sort,
        onChange: (e) => setFilters((f) => ({ ...f, sort: e.target.value })),
        "aria-label": t("Trier", "Sort")
      },
      Object.keys(SORT_LABEL).map((key) => /* @__PURE__ */ React.createElement("option", { key, value: key }, SORT_LABEL[key][lang]))
    ));
  };
  var StatusFilter = ({ filters, setFilters, lang }) => {
    const t = useT();
    return /* @__PURE__ */ React.createElement("div", { className: "chips", style: { marginTop: 10 } }, /* @__PURE__ */ React.createElement(
      "button",
      {
        className: `chip${!filters.status ? " on" : ""}`,
        onClick: () => setFilters((f) => ({ ...f, status: "" }))
      },
      t("Tous statuts", "Any status")
    ), STATUSES.map((status) => /* @__PURE__ */ React.createElement(
      "button",
      {
        key: status,
        className: `chip${filters.status === status ? " on" : ""}`,
        onClick: () => setFilters((f) => ({ ...f, status: f.status === status ? "" : status }))
      },
      STATUS_LABEL[status][lang]
    )));
  };
  var Stats = ({ stats, lang }) => {
    const t = useT();
    if (!stats) return null;
    const cells = [
      [stats.topics, t("sujets", "topics")],
      [stats.ideas, t("id\xE9es", "ideas")],
      [stats.bugs, t("bugs", "bugs")],
      [stats.done, t("livr\xE9s", "shipped")]
    ];
    return /* @__PURE__ */ React.createElement("div", { className: "stats" }, cells.map(([n, label]) => /* @__PURE__ */ React.createElement("div", { className: "stat", key: label }, /* @__PURE__ */ React.createElement("b", null, n), /* @__PURE__ */ React.createElement("span", null, label))));
  };
  var IdentityFields = ({ identity, setIdentity }) => {
    const t = useT();
    return /* @__PURE__ */ React.createElement("div", { className: "row2" }, /* @__PURE__ */ React.createElement("div", { className: "field" }, /* @__PURE__ */ React.createElement("label", { htmlFor: "author" }, t("Votre pseudo", "Your name")), /* @__PURE__ */ React.createElement(
      "input",
      {
        id: "author",
        value: identity.author,
        maxLength: LIMITS.author,
        onChange: (e) => setIdentity({ ...identity, author: e.target.value }),
        placeholder: t("Camille", "Camille"),
        autoComplete: "nickname"
      }
    )), /* @__PURE__ */ React.createElement("div", { className: "field" }, /* @__PURE__ */ React.createElement("label", { htmlFor: "email" }, t("E-mail (facultatif)", "E-mail (optional)")), /* @__PURE__ */ React.createElement(
      "input",
      {
        id: "email",
        type: "email",
        value: identity.email,
        onChange: (e) => setIdentity({ ...identity, email: e.target.value }),
        placeholder: t("pour \xEAtre pr\xE9venu", "to get a reply"),
        autoComplete: "email"
      }
    ), /* @__PURE__ */ React.createElement("p", { className: "hint" }, t(
      "Jamais affich\xE9 publiquement. Sert uniquement \xE0 vous r\xE9pondre.",
      "Never shown publicly. Only used to get back to you."
    ))));
  };
  var NewTopicForm = ({ lang, onCreated, onCancel }) => {
    const t = useT();
    const [kind, setKind] = React.useState("idea");
    const [title, setTitle] = React.useState("");
    const [body, setBody] = React.useState("");
    const [identity, setIdentity] = React.useState(loadIdentity);
    const [website, setWebsite] = React.useState("");
    const [error, setError] = React.useState(null);
    const [sending, setSending] = React.useState(false);
    const submit = async (e) => {
      e.preventDefault();
      if (sending) return;
      setError(null);
      setSending(true);
      try {
        const topic = await api("topic", {
          method: "POST",
          body: {
            kind,
            title,
            body,
            author: identity.author,
            email: identity.email,
            lang,
            website
          }
        });
        saveIdentity(identity);
        rememberToken("topic", topic.id, topic.token);
        onCreated(topic);
      } catch (err) {
        setError(err.code || "server_error");
      } finally {
        setSending(false);
      }
    };
    return /* @__PURE__ */ React.createElement("form", { className: "form", onSubmit: submit }, /* @__PURE__ */ React.createElement("h3", null, t("Nouveau sujet", "New topic")), /* @__PURE__ */ React.createElement("div", { className: "field" }, /* @__PURE__ */ React.createElement("label", null, t("Cat\xE9gorie", "Category")), /* @__PURE__ */ React.createElement("div", { className: "kinds" }, KINDS.map((k) => /* @__PURE__ */ React.createElement(
      "button",
      {
        type: "button",
        key: k,
        className: `kindbtn${kind === k ? " on" : ""}`,
        onClick: () => setKind(k),
        "aria-pressed": kind === k
      },
      /* @__PURE__ */ React.createElement(Icon, { name: KIND_ICON[k], size: 19 }),
      KIND_LABEL[k][lang]
    )))), /* @__PURE__ */ React.createElement("div", { className: "field" }, /* @__PURE__ */ React.createElement("label", { htmlFor: "title" }, t("Titre", "Title"), /* @__PURE__ */ React.createElement(Counter, { value: title.length, max: LIMITS.title })), /* @__PURE__ */ React.createElement(
      "input",
      {
        id: "title",
        value: title,
        maxLength: LIMITS.title,
        required: true,
        onChange: (e) => setTitle(e.target.value),
        placeholder: kind === "bug" ? t("Le lecteur vid\xE9o se fige sur les fichiers MKV", "Video player freezes on MKV files") : t("Pouvoir trier les fichiers par taille", "Let me sort files by size")
      }
    )), /* @__PURE__ */ React.createElement("div", { className: "field" }, /* @__PURE__ */ React.createElement("label", { htmlFor: "body" }, t("Description", "Description"), /* @__PURE__ */ React.createElement(Counter, { value: body.length, max: LIMITS.body })), /* @__PURE__ */ React.createElement(
      "textarea",
      {
        id: "body",
        value: body,
        maxLength: LIMITS.body,
        required: true,
        onChange: (e) => setBody(e.target.value),
        placeholder: kind === "bug" ? t(
          "Ce qui se passe, ce que vous attendiez, votre appareil et la version de l'app.",
          "What happens, what you expected, your device and the app version."
        ) : t(
          "D\xE9crivez votre id\xE9e et ce qu'elle vous permettrait de faire.",
          "Describe your idea and what it would let you do."
        )
      }
    ), /* @__PURE__ */ React.createElement("p", { className: "hint" }, t(
      "Pour un bug, pr\xE9cisez votre appareil, la version d'iOS et celle de l'app \u2014 cela fait gagner un aller-retour.",
      "For a bug, mention your device, your iOS version and the app version \u2014 it saves a round trip."
    ))), /* @__PURE__ */ React.createElement(IdentityFields, { identity, setIdentity }), /* @__PURE__ */ React.createElement("div", { className: "honey", "aria-hidden": "true" }, /* @__PURE__ */ React.createElement("label", { htmlFor: "website" }, "Website"), /* @__PURE__ */ React.createElement(
      "input",
      {
        id: "website",
        tabIndex: "-1",
        autoComplete: "off",
        value: website,
        onChange: (e) => setWebsite(e.target.value)
      }
    )), error && /* @__PURE__ */ React.createElement(Message, null, errorText(error, lang)), /* @__PURE__ */ React.createElement("div", { className: "actions" }, /* @__PURE__ */ React.createElement("button", { className: "btn btn-violet", type: "submit", disabled: sending }, sending ? t("Publication\u2026", "Posting\u2026") : t("Publier", "Post")), /* @__PURE__ */ React.createElement("button", { className: "btn btn-plain", type: "button", onClick: onCancel }, t("Annuler", "Cancel")), /* @__PURE__ */ React.createElement("span", { className: "hint", style: { margin: 0 } }, t(
      "Publi\xE9 imm\xE9diatement et visible publiquement.",
      "Posted immediately and publicly visible."
    ))));
  };
  var ReplyForm = ({ topicId, lang, onReplied }) => {
    const t = useT();
    const [body, setBody] = React.useState("");
    const [identity, setIdentity] = React.useState(loadIdentity);
    const [website, setWebsite] = React.useState("");
    const [error, setError] = React.useState(null);
    const [sending, setSending] = React.useState(false);
    const submit = async (e) => {
      e.preventDefault();
      if (sending) return;
      setError(null);
      setSending(true);
      try {
        const reply = await api("reply", {
          method: "POST",
          body: { topic_id: topicId, body, author: identity.author, email: identity.email, website }
        });
        saveIdentity(identity);
        rememberToken("reply", reply.id, reply.token);
        setBody("");
        onReplied(reply);
      } catch (err) {
        setError(err.code || "server_error");
      } finally {
        setSending(false);
      }
    };
    return /* @__PURE__ */ React.createElement("form", { className: "form", onSubmit: submit }, /* @__PURE__ */ React.createElement("h3", null, t("R\xE9pondre", "Reply")), /* @__PURE__ */ React.createElement("div", { className: "field" }, /* @__PURE__ */ React.createElement("label", { htmlFor: "reply-body" }, t("Votre message", "Your message"), /* @__PURE__ */ React.createElement(Counter, { value: body.length, max: LIMITS.body })), /* @__PURE__ */ React.createElement(
      "textarea",
      {
        id: "reply-body",
        value: body,
        maxLength: LIMITS.body,
        required: true,
        onChange: (e) => setBody(e.target.value),
        placeholder: t("Ajoutez votre exp\xE9rience, un d\xE9tail utile\u2026", "Add your own experience, a useful detail\u2026"),
        style: { minHeight: 100 }
      }
    )), /* @__PURE__ */ React.createElement(IdentityFields, { identity, setIdentity }), /* @__PURE__ */ React.createElement("div", { className: "honey", "aria-hidden": "true" }, /* @__PURE__ */ React.createElement("label", { htmlFor: "reply-website" }, "Website"), /* @__PURE__ */ React.createElement(
      "input",
      {
        id: "reply-website",
        tabIndex: "-1",
        autoComplete: "off",
        value: website,
        onChange: (e) => setWebsite(e.target.value)
      }
    )), error && /* @__PURE__ */ React.createElement(Message, null, errorText(error, lang)), /* @__PURE__ */ React.createElement("div", { className: "actions" }, /* @__PURE__ */ React.createElement("button", { className: "btn btn-violet", type: "submit", disabled: sending }, sending ? t("Envoi\u2026", "Sending\u2026") : t("Envoyer", "Send"))));
  };
  var DeleteOwn = ({ target, id, lang, onDeleted }) => {
    const t = useT();
    const token = tokenFor(target, id);
    const [confirming, setConfirming] = React.useState(false);
    const [error, setError] = React.useState(null);
    if (!token) return null;
    const remove = async () => {
      setError(null);
      try {
        await api("own", { method: "DELETE", params: { target, id, token } });
        onDeleted();
      } catch (err) {
        setError(err.code || "server_error");
      }
    };
    if (error) return /* @__PURE__ */ React.createElement("span", { className: "hint", style: { color: "#a3231a" } }, errorText(error, lang));
    return confirming ? /* @__PURE__ */ React.createElement("span", { style: { display: "inline-flex", gap: 10, alignItems: "center" } }, /* @__PURE__ */ React.createElement("button", { className: "linkish", style: { color: "#a3231a" }, onClick: remove }, t("Confirmer la suppression", "Confirm deletion")), /* @__PURE__ */ React.createElement("button", { className: "linkish", onClick: () => setConfirming(false) }, t("Annuler", "Cancel"))) : /* @__PURE__ */ React.createElement("button", { className: "linkish", onClick: () => setConfirming(true) }, /* @__PURE__ */ React.createElement(Icon, { name: "trash", size: 12 }), " ", t("Supprimer", "Delete"));
  };
  var TopicDetail = ({ id, lang, onBack, onDeleted }) => {
    const t = useT();
    const [topic, setTopic] = React.useState(null);
    const [error, setError] = React.useState(null);
    const load = React.useCallback(async () => {
      setError(null);
      try {
        setTopic(await api("topic", { params: { id } }));
      } catch (err) {
        setError(err.code || "server_error");
      }
    }, [id]);
    React.useEffect(() => {
      load();
    }, [load]);
    if (error) {
      return /* @__PURE__ */ React.createElement("div", { className: "wrap" }, /* @__PURE__ */ React.createElement("button", { className: "back", onClick: onBack }, /* @__PURE__ */ React.createElement(Icon, { name: "back", size: 15 }), t("Retour", "Back")), /* @__PURE__ */ React.createElement(Message, null, errorText(error, lang)));
    }
    if (!topic) {
      return /* @__PURE__ */ React.createElement("div", { className: "wrap" }, /* @__PURE__ */ React.createElement("button", { className: "back", onClick: onBack }, /* @__PURE__ */ React.createElement(Icon, { name: "back", size: 15 }), t("Retour", "Back")), /* @__PURE__ */ React.createElement("div", { className: "skeleton", style: { height: 200, marginTop: 14 } }));
    }
    return /* @__PURE__ */ React.createElement("div", { className: "wrap" }, /* @__PURE__ */ React.createElement("button", { className: "back", onClick: onBack }, /* @__PURE__ */ React.createElement(Icon, { name: "back", size: 15 }), t("Tous les sujets", "All topics")), /* @__PURE__ */ React.createElement("article", { className: "detail" }, /* @__PURE__ */ React.createElement("div", { className: "tmeta" }, /* @__PURE__ */ React.createElement("span", { className: `tag ${topic.kind}` }, KIND_LABEL[topic.kind][lang]), /* @__PURE__ */ React.createElement("span", { className: `status ${topic.status}` }, STATUS_LABEL[topic.status][lang]), topic.pinned && /* @__PURE__ */ React.createElement("span", { className: "status" }, /* @__PURE__ */ React.createElement(Icon, { name: "pin", size: 11 }), " ", t("\xC9pingl\xE9", "Pinned")), topic.locked && /* @__PURE__ */ React.createElement("span", { className: "status" }, /* @__PURE__ */ React.createElement(Icon, { name: "lock", size: 11 }), " ", t("Ferm\xE9", "Closed"))), /* @__PURE__ */ React.createElement("h2", null, topic.title), /* @__PURE__ */ React.createElement("div", { className: "byline" }, /* @__PURE__ */ React.createElement("span", null, topic.author), /* @__PURE__ */ React.createElement("span", null, timeAgo(topic.created_at, lang)), /* @__PURE__ */ React.createElement(DeleteOwn, { target: "topic", id: topic.id, lang, onDeleted })), /* @__PURE__ */ React.createElement("p", { className: "prose" }, topic.body), topic.official_reply && /* @__PURE__ */ React.createElement("div", { className: "official" }, /* @__PURE__ */ React.createElement("div", { className: "lab" }, /* @__PURE__ */ React.createElement(Icon, { name: "check", size: 12 }), " ", t("R\xE9ponse du d\xE9veloppeur", "Developer reply")), /* @__PURE__ */ React.createElement("p", null, topic.official_reply)), /* @__PURE__ */ React.createElement("div", { style: { marginTop: 20 } }, /* @__PURE__ */ React.createElement(VoteButton, { topic, onVoted: (_, res) => setTopic((prev) => ({ ...prev, ...res })) }))), /* @__PURE__ */ React.createElement("h3", { style: { margin: "28px 0 0", fontSize: 17, letterSpacing: "-.3px" } }, topic.replies_list.length === 0 ? t("Aucune r\xE9ponse pour le moment", "No replies yet") : `${topic.replies_list.length} ${topic.replies_list.length === 1 ? t("r\xE9ponse", "reply") : t("r\xE9ponses", "replies")}`), /* @__PURE__ */ React.createElement("div", { className: "replies" }, topic.replies_list.map((reply) => /* @__PURE__ */ React.createElement("div", { className: `reply${reply.staff ? " staff" : ""}`, key: reply.id }, /* @__PURE__ */ React.createElement("div", { className: "rhead" }, /* @__PURE__ */ React.createElement("span", { className: "who" }, reply.author), reply.staff && /* @__PURE__ */ React.createElement("span", { className: "devtag" }, t("D\xE9veloppeur", "Developer")), /* @__PURE__ */ React.createElement("span", { className: "when" }, timeAgo(reply.created_at, lang)), /* @__PURE__ */ React.createElement(DeleteOwn, { target: "reply", id: reply.id, lang, onDeleted: load })), /* @__PURE__ */ React.createElement("p", { className: "rbody" }, reply.body)))), topic.locked ? /* @__PURE__ */ React.createElement("div", { className: "empty", style: { marginTop: 20 } }, /* @__PURE__ */ React.createElement(Icon, { name: "lock", size: 15 }), " ", t("Ce sujet est ferm\xE9 aux nouvelles r\xE9ponses.", "This topic is closed for new replies.")) : /* @__PURE__ */ React.createElement(ReplyForm, { topicId: topic.id, lang, onReplied: load }));
  };
  var PAGE = 20;
  var TopicList = ({ lang, onOpen }) => {
    const t = useT();
    const [filters, setFilters] = React.useState({ kind: "", status: "", sort: "active", q: "" });
    const [state, setState] = React.useState({ items: [], total: 0, loading: true, error: null });
    const [offset, setOffset] = React.useState(0);
    const [stats, setStats] = React.useState(null);
    const [composing, setComposing] = React.useState(false);
    const [posted, setPosted] = React.useState(false);
    React.useEffect(() => {
      setOffset(0);
    }, [filters.kind, filters.status, filters.sort, filters.q]);
    React.useEffect(() => {
      let cancelled = false;
      setState((s) => ({ ...s, loading: true, error: null }));
      api("topics", { params: { ...filters, limit: PAGE, offset } }).then((data) => {
        if (cancelled) return;
        setState((s) => ({
          items: offset === 0 ? data.items : [...s.items, ...data.items],
          total: data.total,
          loading: false,
          error: null
        }));
      }).catch((err) => {
        if (!cancelled) setState((s) => ({ ...s, loading: false, error: err.code || "server_error" }));
      });
      return () => {
        cancelled = true;
      };
    }, [filters.kind, filters.status, filters.sort, filters.q, offset]);
    const loadStats = React.useCallback(() => {
      api("stats").then(setStats).catch(() => setStats(null));
    }, []);
    React.useEffect(() => {
      loadStats();
    }, [loadStats]);
    const onCreated = (topic) => {
      setComposing(false);
      setPosted(true);
      loadStats();
      onOpen(topic.id);
    };
    const { items, total, loading, error } = state;
    const hasMore = items.length < total;
    return /* @__PURE__ */ React.createElement(React.Fragment, null, /* @__PURE__ */ React.createElement("div", { className: "fhead" }, /* @__PURE__ */ React.createElement("div", { className: "wrap" }, /* @__PURE__ */ React.createElement("p", { className: "eyebrow" }, t("Forum public", "Public forum")), /* @__PURE__ */ React.createElement("h1", { className: "ftitle" }, t("Vos id\xE9es font l'app", "Your ideas shape the app")), /* @__PURE__ */ React.createElement("p", { className: "fsub" }, t(
      "Proposez une id\xE9e, signalez un bug, posez une question. Votez pour ce qui compte pour vous \u2014 sans cr\xE9er de compte.",
      "Suggest an idea, report a bug, ask a question. Vote for what matters to you \u2014 no account needed."
    )), /* @__PURE__ */ React.createElement(Stats, { stats, lang }), !composing && /* @__PURE__ */ React.createElement("div", { className: "center" }, /* @__PURE__ */ React.createElement("button", { className: "btn btn-violet", onClick: () => {
      setPosted(false);
      setComposing(true);
    } }, /* @__PURE__ */ React.createElement(Icon, { name: "plus", size: 17 }), t("Nouveau sujet", "New topic"))))), /* @__PURE__ */ React.createElement("div", { className: "wrap" }, composing && /* @__PURE__ */ React.createElement(NewTopicForm, { lang, onCreated, onCancel: () => setComposing(false) }), posted && !composing && /* @__PURE__ */ React.createElement(Message, { kind: "ok" }, t("Merci ! Votre message est en ligne.", "Thanks! Your post is live.")), /* @__PURE__ */ React.createElement(Filters, { filters, setFilters, lang }), /* @__PURE__ */ React.createElement(StatusFilter, { filters, setFilters, lang }), error && /* @__PURE__ */ React.createElement(Message, null, errorText(error, lang)), loading && offset === 0 && !error && /* @__PURE__ */ React.createElement("div", { className: "list" }, [0, 1, 2, 3].map((i) => /* @__PURE__ */ React.createElement("div", { className: "skeleton", key: i }))), !loading && !error && items.length === 0 && /* @__PURE__ */ React.createElement("div", { className: "empty" }, filters.q || filters.kind || filters.status ? t("Aucun sujet ne correspond \xE0 ce filtre.", "No topic matches these filters.") : t("Rien ici pour l'instant \u2014 lancez la premi\xE8re discussion !", "Nothing here yet \u2014 start the first discussion!")), items.length > 0 && /* @__PURE__ */ React.createElement("div", { className: "list" }, items.map((topic) => /* @__PURE__ */ React.createElement(TopicRow, { key: topic.id, topic, lang, onOpen }))), hasMore && !error && /* @__PURE__ */ React.createElement("div", { className: "center" }, /* @__PURE__ */ React.createElement(
      "button",
      {
        className: "btn btn-plain",
        disabled: loading,
        onClick: () => setOffset(items.length)
      },
      loading ? t("Chargement\u2026", "Loading\u2026") : t("Voir plus de sujets", "Show more topics")
    ))));
  };
  var topicIdFromHash = () => {
    const match = /^#\/t\/(\d+)$/.exec(window.location.hash || "");
    return match ? Number(match[1]) : null;
  };
  var detectLang = () => {
    const saved = store.read("lang", null);
    if (saved === "fr" || saved === "en") return saved;
    return (navigator.language || "en").toLowerCase().startsWith("fr") ? "fr" : "en";
  };
  var App = () => {
    const [lang, setLangState] = React.useState(detectLang);
    const [topicId, setTopicId] = React.useState(topicIdFromHash);
    React.useEffect(() => {
      const onHash = () => setTopicId(topicIdFromHash());
      window.addEventListener("hashchange", onHash);
      return () => window.removeEventListener("hashchange", onHash);
    }, []);
    React.useEffect(() => {
      document.documentElement.lang = lang;
    }, [lang]);
    const setLang = (next) => {
      setLangState(next);
      store.write("lang", next);
    };
    const openTopic = (id) => {
      window.location.hash = `#/t/${id}`;
      setTopicId(id);
      window.scrollTo({ top: 0, behavior: "smooth" });
    };
    const backToList = () => {
      window.location.hash = "";
      setTopicId(null);
    };
    return /* @__PURE__ */ React.createElement(LangContext.Provider, { value: lang }, /* @__PURE__ */ React.createElement(Header, { lang, setLang }), topicId ? /* @__PURE__ */ React.createElement(TopicDetail, { id: topicId, lang, onBack: backToList, onDeleted: backToList }) : /* @__PURE__ */ React.createElement(TopicList, { lang, onOpen: openTopic }), /* @__PURE__ */ React.createElement(Footer, null));
  };
  ReactDOM.createRoot(document.getElementById("root")).render(/* @__PURE__ */ React.createElement(App, null));
})();
