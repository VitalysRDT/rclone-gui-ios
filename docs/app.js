/* ════════════════════════════════════════════════════════════════════
   Config
   ════════════════════════════════════════════════════════════════════ */
const APP_ID = '6770088773';
const APP_STORE_URL = 'https://apps.apple.com/app/id' + APP_ID;
const GITHUB_URL = 'https://github.com/VitalysRDT/rclone-gui-ios';
// Backend qui distribue 1 code par utilisateur (les codes ne sont JAMAIS dans cette page).
const CLAIM_API = 'https://rclone-gui-trial.vercel.app/api/claim';

/* ════════════════════════════════════════════════════════════════════
   Design system (repris du handoff design — DesignSystem.swift)
   ════════════════════════════════════════════════════════════════════ */
const ACCENT = '#7C3AED';
const ACCENT_DEEP = '#5B21B6';
const ACCENT_SOFT = 'rgba(124, 58, 237, 0.18)';
const LangContext = React.createContext('en');
const useT = () => {
  const lang = React.useContext(LangContext);
  return (fr, en) => lang === 'fr' ? fr : en === undefined ? fr : en;
};
const BACKEND_COLORS = {
  s3: '#FF9500',
  b2: '#E5392F',
  sftp: '#34C759',
  ftp: '#008099',
  webdav: '#5856D6',
  drive: '#1A73E8',
  dropbox: '#0061FF',
  onedrive: '#0364B8',
  box: '#0061D5',
  crypt: ACCENT,
  local: '#8E8E93',
  mega: '#D9272E',
  pcloud: '#16A085',
  storj: '#2683FF',
  wasabi: '#01B636',
  generic: '#8E8E93'
};
const BACKEND_GLYPHS = {
  s3: 'cloud.fill',
  b2: 'cloud.fill',
  drive: 'cloud.fill',
  dropbox: 'cloud.fill',
  onedrive: 'cloud.fill',
  box: 'cloud.fill',
  mega: 'cloud.fill',
  pcloud: 'cloud.fill',
  storj: 'cloud.fill',
  wasabi: 'cloud.fill',
  sftp: 'server',
  ftp: 'server',
  webdav: 'globe',
  crypt: 'lock.fill',
  local: 'folder.fill'
};
const Icon = ({
  name,
  size = 18,
  weight = 'regular',
  style
}) => {
  const sw = weight === 'bold' ? 2.4 : weight === 'semibold' ? 2 : 1.7;
  const common = {
    width: size,
    height: size,
    viewBox: '0 0 24 24',
    fill: 'none',
    stroke: 'currentColor',
    strokeWidth: sw,
    strokeLinecap: 'round',
    strokeLinejoin: 'round',
    style
  };
  switch (name) {
    case 'lock':
      return /*#__PURE__*/React.createElement("svg", common, /*#__PURE__*/React.createElement("rect", {
        x: "4.5",
        y: "10.5",
        width: "15",
        height: "10.5",
        rx: "2.5"
      }), /*#__PURE__*/React.createElement("path", {
        d: "M7.5 10.5V7a4.5 4.5 0 1 1 9 0v3.5"
      }));
    case 'lock.fill':
      return /*#__PURE__*/React.createElement("svg", {
        ...common,
        fill: "currentColor",
        stroke: "none"
      }, /*#__PURE__*/React.createElement("path", {
        d: "M7.5 7a4.5 4.5 0 1 1 9 0v3.5h-2V7a2.5 2.5 0 0 0-5 0v3.5h-2V7Z"
      }), /*#__PURE__*/React.createElement("rect", {
        x: "4.5",
        y: "10.5",
        width: "15",
        height: "10.5",
        rx: "2.5"
      }));
    case 'cloud':
      return /*#__PURE__*/React.createElement("svg", common, /*#__PURE__*/React.createElement("path", {
        d: "M7 18a4 4 0 0 1-.6-7.95 5.5 5.5 0 0 1 10.7-.7A4 4 0 0 1 17 18H7Z"
      }));
    case 'cloud.fill':
      return /*#__PURE__*/React.createElement("svg", {
        ...common,
        fill: "currentColor",
        stroke: "none"
      }, /*#__PURE__*/React.createElement("path", {
        d: "M7 18a4 4 0 0 1-.6-7.95 5.5 5.5 0 0 1 10.7-.7A4 4 0 0 1 17 18H7Z"
      }));
    case 'folder':
      return /*#__PURE__*/React.createElement("svg", common, /*#__PURE__*/React.createElement("path", {
        d: "M3.5 7.5A1.5 1.5 0 0 1 5 6h4l2 2h8a1.5 1.5 0 0 1 1.5 1.5v8A1.5 1.5 0 0 1 19 19H5a1.5 1.5 0 0 1-1.5-1.5v-10Z"
      }));
    case 'folder.fill':
      return /*#__PURE__*/React.createElement("svg", {
        ...common,
        fill: "currentColor",
        stroke: "currentColor"
      }, /*#__PURE__*/React.createElement("path", {
        d: "M3.5 7.5A1.5 1.5 0 0 1 5 6h4l2 2h8a1.5 1.5 0 0 1 1.5 1.5v8A1.5 1.5 0 0 1 19 19H5a1.5 1.5 0 0 1-1.5-1.5v-10Z"
      }));
    case 'externaldrive':
      return /*#__PURE__*/React.createElement("svg", common, /*#__PURE__*/React.createElement("rect", {
        x: "3",
        y: "6",
        width: "18",
        height: "12",
        rx: "2.5"
      }), /*#__PURE__*/React.createElement("circle", {
        cx: "17",
        cy: "12",
        r: "1",
        fill: "currentColor"
      }), /*#__PURE__*/React.createElement("path", {
        d: "M7 12h6"
      }));
    case 'server':
      return /*#__PURE__*/React.createElement("svg", common, /*#__PURE__*/React.createElement("rect", {
        x: "3.5",
        y: "4",
        width: "17",
        height: "6",
        rx: "1.5"
      }), /*#__PURE__*/React.createElement("rect", {
        x: "3.5",
        y: "14",
        width: "17",
        height: "6",
        rx: "1.5"
      }), /*#__PURE__*/React.createElement("circle", {
        cx: "7",
        cy: "7",
        r: ".7",
        fill: "currentColor"
      }), /*#__PURE__*/React.createElement("circle", {
        cx: "7",
        cy: "17",
        r: ".7",
        fill: "currentColor"
      }));
    case 'gear':
      return /*#__PURE__*/React.createElement("svg", common, /*#__PURE__*/React.createElement("circle", {
        cx: "12",
        cy: "12",
        r: "3"
      }), /*#__PURE__*/React.createElement("path", {
        d: "M19.4 14a1.6 1.6 0 0 0 .3 1.7l.05.05a2 2 0 0 1-2.83 2.83l-.05-.05a1.6 1.6 0 0 0-1.7-.3 1.6 1.6 0 0 0-1 1.46V20a2 2 0 0 1-4 0v-.08a1.6 1.6 0 0 0-1-1.46 1.6 1.6 0 0 0-1.7.3l-.05.05a2 2 0 0 1-2.83-2.83l.05-.05a1.6 1.6 0 0 0 .3-1.7 1.6 1.6 0 0 0-1.46-1H4a2 2 0 0 1 0-4h.08a1.6 1.6 0 0 0 1.46-1 1.6 1.6 0 0 0-.3-1.7l-.05-.05a2 2 0 0 1 2.83-2.83l.05.05a1.6 1.6 0 0 0 1.7.3h.01a1.6 1.6 0 0 0 1-1.46V4a2 2 0 0 1 4 0v.08a1.6 1.6 0 0 0 1 1.46 1.6 1.6 0 0 0 1.7-.3l.05-.05a2 2 0 0 1 2.83 2.83l-.05.05a1.6 1.6 0 0 0-.3 1.7v.01a1.6 1.6 0 0 0 1.46 1H20a2 2 0 0 1 0 4h-.08a1.6 1.6 0 0 0-1.46 1Z"
      }));
    case 'arrows':
      return /*#__PURE__*/React.createElement("svg", common, /*#__PURE__*/React.createElement("path", {
        d: "M7 4v14M7 18l-3-3M7 18l3-3"
      }), /*#__PURE__*/React.createElement("path", {
        d: "M17 20V6M17 6l-3 3M17 6l3 3"
      }));
    case 'chevron.right':
      return /*#__PURE__*/React.createElement("svg", common, /*#__PURE__*/React.createElement("path", {
        d: "M9 6l6 6-6 6"
      }));
    case 'check':
      return /*#__PURE__*/React.createElement("svg", common, /*#__PURE__*/React.createElement("path", {
        d: "M5 12.5l4.5 4.5L19 7.5"
      }));
    case 'check.circle':
      return /*#__PURE__*/React.createElement("svg", {
        ...common,
        fill: "currentColor",
        stroke: "none"
      }, /*#__PURE__*/React.createElement("path", {
        d: "M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20Zm-1.2 14L6.5 11.7l1.4-1.4 2.9 2.9 5.3-5.3 1.4 1.4-6.7 6.7Z"
      }));
    case 'plus':
      return /*#__PURE__*/React.createElement("svg", common, /*#__PURE__*/React.createElement("path", {
        d: "M12 5v14M5 12h14"
      }));
    case 'plus.circle':
      return /*#__PURE__*/React.createElement("svg", common, /*#__PURE__*/React.createElement("circle", {
        cx: "12",
        cy: "12",
        r: "9"
      }), /*#__PURE__*/React.createElement("path", {
        d: "M12 8v8M8 12h8"
      }));
    case 'magnifying':
      return /*#__PURE__*/React.createElement("svg", common, /*#__PURE__*/React.createElement("circle", {
        cx: "11",
        cy: "11",
        r: "6.5"
      }), /*#__PURE__*/React.createElement("path", {
        d: "M16 16l4 4"
      }));
    case 'clock':
      return /*#__PURE__*/React.createElement("svg", common, /*#__PURE__*/React.createElement("circle", {
        cx: "12",
        cy: "12",
        r: "9"
      }), /*#__PURE__*/React.createElement("path", {
        d: "M12 7v5l3 2"
      }));
    case 'bolt.fill':
      return /*#__PURE__*/React.createElement("svg", {
        ...common,
        fill: "currentColor",
        stroke: "none"
      }, /*#__PURE__*/React.createElement("path", {
        d: "M14 2 5 13h6l-1 9 9-11h-6l1-9Z"
      }));
    case 'photo':
      return /*#__PURE__*/React.createElement("svg", common, /*#__PURE__*/React.createElement("rect", {
        x: "3",
        y: "5",
        width: "18",
        height: "14",
        rx: "2"
      }), /*#__PURE__*/React.createElement("circle", {
        cx: "9",
        cy: "10.5",
        r: "1.5"
      }), /*#__PURE__*/React.createElement("path", {
        d: "m3 18 5-5 4 4 3-3 6 6"
      }));
    case 'photo.stack':
      return /*#__PURE__*/React.createElement("svg", common, /*#__PURE__*/React.createElement("rect", {
        x: "5",
        y: "7",
        width: "16",
        height: "12",
        rx: "2"
      }), /*#__PURE__*/React.createElement("path", {
        d: "M3 9v9a2 2 0 0 0 2 2h11"
      }), /*#__PURE__*/React.createElement("circle", {
        cx: "11",
        cy: "12",
        r: "1.5"
      }), /*#__PURE__*/React.createElement("path", {
        d: "m7 18 4-4 3 3 2-2 5 5"
      }));
    case 'shield.fill':
      return /*#__PURE__*/React.createElement("svg", {
        ...common,
        fill: "currentColor",
        stroke: "none"
      }, /*#__PURE__*/React.createElement("path", {
        d: "M12 3 4 6v6c0 5 3.5 8.5 8 9 4.5-.5 8-4 8-9V6l-8-3Zm-1.2 13L6.5 11.7 7.9 10.3 10.8 13.2 16.1 7.9 17.5 9.3 10.8 16Z"
      }));
    case 'faceid':
      return /*#__PURE__*/React.createElement("svg", common, /*#__PURE__*/React.createElement("path", {
        d: "M5 8V6a1 1 0 0 1 1-1h2M19 8V6a1 1 0 0 0-1-1h-2M5 16v2a1 1 0 0 0 1 1h2M19 16v2a1 1 0 0 1-1 1h-2"
      }), /*#__PURE__*/React.createElement("path", {
        d: "M9 10v2M15 10v2M12 9v4l-1.5 1M9.5 15.5s1 1 2.5 1 2.5-1 2.5-1"
      }));
    case 'sparkles':
      return /*#__PURE__*/React.createElement("svg", common, /*#__PURE__*/React.createElement("path", {
        d: "M12 4v3M12 17v3M4 12h3M17 12h3M6.5 6.5l2 2M15.5 15.5l2 2M17.5 6.5l-2 2M8.5 15.5l-2 2"
      }));
    case 'doc':
      return /*#__PURE__*/React.createElement("svg", common, /*#__PURE__*/React.createElement("path", {
        d: "M7 3h7l5 5v12a1.5 1.5 0 0 1-1.5 1.5h-10.5A1.5 1.5 0 0 1 5.5 20V4.5A1.5 1.5 0 0 1 7 3Z"
      }), /*#__PURE__*/React.createElement("path", {
        d: "M14 3v5h5"
      }));
    case 'play.fill':
      return /*#__PURE__*/React.createElement("svg", {
        ...common,
        fill: "currentColor",
        stroke: "none"
      }, /*#__PURE__*/React.createElement("path", {
        d: "M7 4.5v15l13-7.5L7 4.5Z"
      }));
    case 'download':
      return /*#__PURE__*/React.createElement("svg", common, /*#__PURE__*/React.createElement("path", {
        d: "M12 4v12M7 11l5 5 5-5M4 20h16"
      }));
    case 'share':
      return /*#__PURE__*/React.createElement("svg", common, /*#__PURE__*/React.createElement("path", {
        d: "M12 3v13M8 7l4-4 4 4"
      }), /*#__PURE__*/React.createElement("path", {
        d: "M5 12v7a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-7"
      }));
    case 'star.fill':
      return /*#__PURE__*/React.createElement("svg", {
        ...common,
        fill: "currentColor",
        stroke: "none"
      }, /*#__PURE__*/React.createElement("path", {
        d: "m12 3 2.7 5.7 6.3.9-4.6 4.4 1.1 6.2L12 17.3l-5.5 2.9 1.1-6.2-4.6-4.4 6.3-.9L12 3Z"
      }));
    case 'wifi':
      return /*#__PURE__*/React.createElement("svg", common, /*#__PURE__*/React.createElement("path", {
        d: "M2 8.5a16 16 0 0 1 20 0M5 12a11 11 0 0 1 14 0M8.5 15.5a6 6 0 0 1 7 0"
      }), /*#__PURE__*/React.createElement("circle", {
        cx: "12",
        cy: "19",
        r: "1.2",
        fill: "currentColor"
      }));
    case 'speedometer':
      return /*#__PURE__*/React.createElement("svg", common, /*#__PURE__*/React.createElement("path", {
        d: "M3 13a9 9 0 1 1 18 0"
      }), /*#__PURE__*/React.createElement("path", {
        d: "M12 13l4.5-4.5"
      }), /*#__PURE__*/React.createElement("circle", {
        cx: "12",
        cy: "13",
        r: "1.3",
        fill: "currentColor"
      }));
    case 'tray':
      return /*#__PURE__*/React.createElement("svg", common, /*#__PURE__*/React.createElement("path", {
        d: "M3 14h4l1 2h8l1-2h4M4 14 6 5a1 1 0 0 1 1-.8h10a1 1 0 0 1 1 .8L20 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1Z"
      }));
    case 'film':
      return /*#__PURE__*/React.createElement("svg", common, /*#__PURE__*/React.createElement("rect", {
        x: "3.5",
        y: "4",
        width: "17",
        height: "16",
        rx: "2"
      }), /*#__PURE__*/React.createElement("path", {
        d: "M7 4v16M17 4v16M3.5 9h3.5M17 9h3.5M3.5 15h3.5M17 15h3.5M7 12h10"
      }));
    case 'music':
      return /*#__PURE__*/React.createElement("svg", common, /*#__PURE__*/React.createElement("path", {
        d: "M9 18V6l11-2v12"
      }), /*#__PURE__*/React.createElement("circle", {
        cx: "6",
        cy: "18",
        r: "2.5"
      }), /*#__PURE__*/React.createElement("circle", {
        cx: "17",
        cy: "16",
        r: "2.5"
      }));
    case 'key':
      return /*#__PURE__*/React.createElement("svg", common, /*#__PURE__*/React.createElement("circle", {
        cx: "8",
        cy: "15",
        r: "3.5"
      }), /*#__PURE__*/React.createElement("path", {
        d: "m10.5 12.5 8-8M15 8l3 3M13 10l2.5 2.5"
      }));
    case 'globe':
      return /*#__PURE__*/React.createElement("svg", common, /*#__PURE__*/React.createElement("circle", {
        cx: "12",
        cy: "12",
        r: "9"
      }), /*#__PURE__*/React.createElement("path", {
        d: "M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"
      }));
    case 'wand':
      return /*#__PURE__*/React.createElement("svg", common, /*#__PURE__*/React.createElement("path", {
        d: "m4 20 12-12M14 6l4 4M11 3l1 2M19 11l2 1M16 14l1 2M6 5l2 1"
      }));
    case 'arrow.up':
      return /*#__PURE__*/React.createElement("svg", common, /*#__PURE__*/React.createElement("path", {
        d: "M12 19V5M6 11l6-6 6 6"
      }));
    case 'rotate':
      return /*#__PURE__*/React.createElement("svg", common, /*#__PURE__*/React.createElement("path", {
        d: "M3 12a9 9 0 0 1 15.4-6.4L21 8M21 4v4h-4M21 12a9 9 0 0 1-15.4 6.4L3 16M3 20v-4h4"
      }));
    default:
      return /*#__PURE__*/React.createElement("svg", common, /*#__PURE__*/React.createElement("rect", {
        x: "4",
        y: "4",
        width: "16",
        height: "16",
        rx: "3"
      }));
  }
};
const BackendChip = ({
  kind,
  size = 40,
  cryptOverlay = false
}) => {
  const color = BACKEND_COLORS[kind] || BACKEND_COLORS.generic;
  const glyph = BACKEND_GLYPHS[kind] || 'cloud.fill';
  const r = size * 0.27;
  return /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'relative',
      width: size + (cryptOverlay ? 4 : 0),
      height: size + (cryptOverlay ? 4 : 0)
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: size,
      height: size,
      borderRadius: r,
      background: color,
      color: 'white',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      boxShadow: `0 2px 4px ${color}33`,
      border: '0.5px solid rgba(255,255,255,0.18)'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: glyph,
    size: size * 0.5,
    weight: "semibold"
  })), cryptOverlay && /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      right: -2,
      bottom: -2,
      width: size * 0.42,
      height: size * 0.42,
      borderRadius: '50%',
      background: ACCENT,
      color: 'white',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      border: '2px solid white'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "lock.fill",
    size: size * 0.22,
    weight: "bold"
  })));
};
const CryptBadge = ({
  size = 1
}) => /*#__PURE__*/React.createElement("span", {
  style: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: 3 * size,
    color: ACCENT,
    background: ACCENT_SOFT,
    padding: `${2 * size}px ${5 * size}px`,
    borderRadius: 4 * size,
    fontWeight: 700,
    fontSize: 10 * size,
    letterSpacing: 0.4 * size
  }
}, /*#__PURE__*/React.createElement(Icon, {
  name: "lock.fill",
  size: 9 * size,
  weight: "bold"
}), "CRYPT");
const CryptSeal = ({
  size = 120
}) => /*#__PURE__*/React.createElement("div", {
  style: {
    position: 'relative',
    width: size + 6,
    height: size + 6
  }
}, /*#__PURE__*/React.createElement("div", {
  style: {
    width: size,
    height: size,
    borderRadius: size * 0.25,
    background: `linear-gradient(135deg, ${ACCENT}, ${ACCENT_DEEP})`,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    color: 'white',
    boxShadow: `0 14px 36px ${ACCENT}55, inset 0 0 0 1px rgba(255,255,255,0.25)`
  }
}, /*#__PURE__*/React.createElement(Icon, {
  name: "lock.fill",
  size: size * 0.5,
  weight: "semibold"
})), /*#__PURE__*/React.createElement("div", {
  style: {
    position: 'absolute',
    top: -size * 0.04,
    right: -size * 0.04,
    width: size * 0.27,
    height: size * 0.27,
    borderRadius: '50%',
    background: '#34C759',
    color: 'white',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    border: '3px solid white'
  }
}, /*#__PURE__*/React.createElement(Icon, {
  name: "check",
  size: size * 0.13,
  weight: "bold"
})));
const GradientAvatar = ({
  initials,
  size = 48
}) => /*#__PURE__*/React.createElement("div", {
  style: {
    width: size,
    height: size,
    borderRadius: '50%',
    background: `linear-gradient(135deg, ${ACCENT}, ${ACCENT_DEEP})`,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    color: 'white',
    fontWeight: 600,
    fontSize: size * 0.38
  }
}, initials);
const StatusBar = ({
  scale = 1
}) => {
  const color = '#000';
  return /*#__PURE__*/React.createElement("div", {
    style: {
      height: 54 * scale,
      padding: `0 ${44 * scale}px`,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      color,
      fontSize: 17 * scale,
      fontWeight: 600,
      fontFamily: '-apple-system, "SF Pro Text", system-ui'
    }
  }, /*#__PURE__*/React.createElement("span", null, "9:41"), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 5 * scale
    }
  }, /*#__PURE__*/React.createElement("svg", {
    width: 18 * scale,
    height: 11 * scale,
    viewBox: "0 0 18 11",
    fill: color
  }, /*#__PURE__*/React.createElement("rect", {
    x: "0",
    y: "7",
    width: "3",
    height: "4",
    rx: "0.5"
  }), /*#__PURE__*/React.createElement("rect", {
    x: "5",
    y: "5",
    width: "3",
    height: "6",
    rx: "0.5"
  }), /*#__PURE__*/React.createElement("rect", {
    x: "10",
    y: "2.5",
    width: "3",
    height: "8.5",
    rx: "0.5"
  }), /*#__PURE__*/React.createElement("rect", {
    x: "15",
    y: "0",
    width: "3",
    height: "11",
    rx: "0.5"
  })), /*#__PURE__*/React.createElement("svg", {
    width: 17 * scale,
    height: 12 * scale,
    viewBox: "0 0 17 12",
    fill: color
  }, /*#__PURE__*/React.createElement("path", {
    d: "M8.5 2.5c2.7 0 5.1 1 7 2.6l-1.3 1.6A8.5 8.5 0 0 0 8.5 5a8.5 8.5 0 0 0-5.7 2.1L1.5 5.5A11 11 0 0 1 8.5 2.5Zm0 3.5c1.8 0 3.5.7 4.7 1.8l-1.3 1.6c-.9-.8-2.1-1.4-3.4-1.4-1.3 0-2.5.6-3.4 1.4L3.8 7.8c1.2-1.1 2.9-1.8 4.7-1.8Zm0 3.5c1 0 1.8.4 2.4 1l-2.4 2.5-2.4-2.5c.6-.6 1.4-1 2.4-1Z"
  })), /*#__PURE__*/React.createElement("svg", {
    width: 28 * scale,
    height: 12 * scale,
    viewBox: "0 0 28 12"
  }, /*#__PURE__*/React.createElement("rect", {
    x: "0.5",
    y: "0.5",
    width: "23",
    height: "11",
    rx: "2.5",
    fill: "none",
    stroke: color,
    strokeOpacity: "0.45"
  }), /*#__PURE__*/React.createElement("rect", {
    x: "2",
    y: "2",
    width: "20",
    height: "8",
    rx: "1.5",
    fill: color
  }), /*#__PURE__*/React.createElement("rect", {
    x: "24.5",
    y: "3.5",
    width: "2.5",
    height: "5",
    rx: "1",
    fill: color,
    opacity: "0.45"
  }))));
};
const NavHeader = ({
  title,
  scale = 1,
  trailing
}) => /*#__PURE__*/React.createElement("div", {
  style: {
    padding: `${4 * scale}px ${20 * scale}px ${14 * scale}px`,
    display: 'flex',
    alignItems: 'flex-end',
    justifyContent: 'space-between'
  }
}, /*#__PURE__*/React.createElement("h1", {
  style: {
    fontSize: 34 * scale,
    fontWeight: 700,
    letterSpacing: -0.5 * scale,
    margin: 0,
    color: '#000'
  }
}, title), trailing);
const TabBar = ({
  active = 'remotes',
  scale = 1
}) => {
  const t = useT();
  const items = [{
    id: 'home',
    label: t('Accueil', 'Home'),
    icon: 'sparkles'
  }, {
    id: 'remotes',
    label: t('Remotes', 'Remotes'),
    icon: 'externaldrive'
  }, {
    id: 'transfers',
    label: t('Transferts', 'Transfers'),
    icon: 'arrows'
  }, {
    id: 'settings',
    label: t('Réglages', 'Settings'),
    icon: 'gear'
  }];
  return /*#__PURE__*/React.createElement("div", {
    style: {
      borderTop: '0.5px solid rgba(60,60,67,0.18)',
      background: 'rgba(247,247,248,0.85)',
      backdropFilter: 'blur(20px)',
      display: 'flex',
      justifyContent: 'space-around',
      padding: `${8 * scale}px 0 ${28 * scale}px`
    }
  }, items.map(item => /*#__PURE__*/React.createElement("div", {
    key: item.id,
    style: {
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      gap: 2 * scale,
      color: item.id === active ? ACCENT : '#8E8E93'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: item.icon,
    size: 26 * scale,
    weight: "regular"
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 10 * scale,
      fontWeight: 500
    }
  }, item.label))));
};
const ListRow = ({
  leading,
  title,
  subtitle,
  trailing,
  scale = 1,
  divider = true
}) => /*#__PURE__*/React.createElement("div", {
  style: {
    display: 'flex',
    alignItems: 'center',
    gap: 12 * scale,
    padding: `${12 * scale}px ${16 * scale}px`,
    borderBottom: divider ? '0.5px solid rgba(60,60,67,0.18)' : 'none'
  }
}, leading, /*#__PURE__*/React.createElement("div", {
  style: {
    flex: 1,
    minWidth: 0
  }
}, /*#__PURE__*/React.createElement("div", {
  style: {
    fontSize: 17 * scale,
    fontWeight: 500,
    color: '#000',
    display: 'flex',
    alignItems: 'center',
    gap: 6 * scale
  }
}, title), subtitle && /*#__PURE__*/React.createElement("div", {
  style: {
    fontSize: 13 * scale,
    color: '#8E8E93',
    marginTop: 2 * scale
  }
}, subtitle)), trailing);

/* ════════════════════════════════════════════════════════════════════
   8 écrans (440 × 956) — repris verbatim du handoff
   ════════════════════════════════════════════════════════════════════ */
const SCREEN_W = 440,
  SCREEN_H = 956;
const ScreenFrame = ({
  children,
  bg = '#F2F2F7'
}) => /*#__PURE__*/React.createElement("div", {
  style: {
    width: SCREEN_W,
    height: SCREEN_H,
    background: bg,
    position: 'relative',
    overflow: 'hidden',
    fontFamily: '-apple-system, "SF Pro Text", system-ui, sans-serif',
    color: '#000',
    display: 'flex',
    flexDirection: 'column'
  }
}, children);
const ScreenOnboarding = () => {
  const t = useT();
  return /*#__PURE__*/React.createElement(ScreenFrame, {
    bg: "#FFFFFF"
  }, /*#__PURE__*/React.createElement(StatusBar, null), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      padding: '40px 28px 0'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 40
    }
  }, /*#__PURE__*/React.createElement(CryptSeal, {
    size: 132
  })), /*#__PURE__*/React.createElement("h1", {
    style: {
      fontSize: 32,
      fontWeight: 700,
      marginTop: 28,
      marginBottom: 6,
      letterSpacing: -0.6
    }
  }, t('Bienvenue dans Rclone', 'Welcome to Rclone')), /*#__PURE__*/React.createElement("p", {
    style: {
      fontSize: 16,
      color: '#3C3C43',
      textAlign: 'center',
      marginTop: 18,
      lineHeight: 1.4,
      maxWidth: 340
    }
  }, t('Tous tes remotes — y compris chiffrés — accessibles depuis Fichiers, en streaming et hors-ligne.', 'All your remotes — encrypted ones included — right inside Files, streaming and offline.')), /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 40,
      width: '100%',
      display: 'flex',
      flexDirection: 'column',
      gap: 14
    }
  }, [{
    icon: 'lock.fill',
    tint: ACCENT,
    title: t('Crypt rclone natif', 'Native rclone crypt'),
    sub: t('AES-256, noms déchiffrés à la volée', 'AES-256, filenames decrypted on the fly')
  }, {
    icon: 'cloud.fill',
    tint: '#1A73E8',
    title: t('80+ backends', '80+ backends'),
    sub: 'S3, R2, Drive, Dropbox, SFTP, B2…'
  }, {
    icon: 'folder.fill',
    tint: '#FF9500',
    title: t('Intégration Fichiers', 'Files integration'),
    sub: t('Chaque remote = un emplacement natif', 'Every remote = a native location')
  }].map(f => /*#__PURE__*/React.createElement("div", {
    key: f.title,
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 14
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: 42,
      height: 42,
      borderRadius: 11,
      background: f.tint + '2E',
      color: f.tint,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: f.icon,
    size: 20,
    weight: "semibold"
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 16,
      fontWeight: 600
    }
  }, f.title), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 13,
      color: '#8E8E93',
      marginTop: 1
    }
  }, f.sub)))))), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 28px 36px'
    }
  }, /*#__PURE__*/React.createElement("button", {
    style: {
      width: '100%',
      padding: '15px 0',
      borderRadius: 14,
      border: 'none',
      background: ACCENT,
      color: '#fff',
      fontSize: 17,
      fontWeight: 600,
      boxShadow: `0 6px 18px ${ACCENT}55`
    }
  }, t('Importer un rclone.conf', 'Import an rclone.conf')), /*#__PURE__*/React.createElement("button", {
    style: {
      width: '100%',
      padding: '14px 0',
      borderRadius: 14,
      border: 'none',
      background: 'transparent',
      color: ACCENT,
      fontSize: 17,
      fontWeight: 500,
      marginTop: 6
    }
  }, t('Créer un Passeport Crypt', 'Create a Crypt Passport')), /*#__PURE__*/React.createElement("p", {
    style: {
      textAlign: 'center',
      fontSize: 13,
      color: '#8E8E93',
      marginTop: 8
    }
  }, t('Tes clés ne quittent jamais l\'iPhone', 'Your keys never leave the iPhone'))));
};
const REMOTES = [{
  name: 'photos-archive',
  sub: {
    fr: 'Crypt sur B2',
    en: 'Crypt on B2'
  },
  chip: 'b2',
  crypt: true
}, {
  name: 'work-drive',
  sub: {
    fr: 'Google Drive',
    en: 'Google Drive'
  },
  chip: 'drive',
  crypt: false
}, {
  name: 'backups-r2',
  sub: {
    fr: 'Crypt sur Cloudflare R2',
    en: 'Crypt on Cloudflare R2'
  },
  chip: 's3',
  crypt: true
}, {
  name: 'media',
  sub: {
    fr: 'AWS S3 (eu-west-3)',
    en: 'AWS S3 (eu-west-3)'
  },
  chip: 's3',
  crypt: false
}, {
  name: 'home-nas',
  sub: {
    fr: 'SFTP — synology.local',
    en: 'SFTP — synology.local'
  },
  chip: 'sftp',
  crypt: false
}, {
  name: 'family-onedrive',
  sub: {
    fr: 'Microsoft OneDrive',
    en: 'Microsoft OneDrive'
  },
  chip: 'onedrive',
  crypt: false
}, {
  name: 'archive-storj',
  sub: {
    fr: 'Crypt sur Storj DCS',
    en: 'Crypt on Storj DCS'
  },
  chip: 'storj',
  crypt: true
}, {
  name: 'shared-dropbox',
  sub: {
    fr: 'Dropbox',
    en: 'Dropbox'
  },
  chip: 'dropbox',
  crypt: false
}];
const ScreenRemotes = () => {
  const t = useT();
  return /*#__PURE__*/React.createElement(ScreenFrame, {
    bg: "#F2F2F7"
  }, /*#__PURE__*/React.createElement(StatusBar, null), /*#__PURE__*/React.createElement(NavHeader, {
    title: "Remotes",
    trailing: /*#__PURE__*/React.createElement("div", {
      style: {
        display: 'flex',
        gap: 18,
        color: ACCENT,
        paddingBottom: 6
      }
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "magnifying",
      size: 22,
      weight: "semibold"
    }), /*#__PURE__*/React.createElement(Icon, {
      name: "plus",
      size: 24,
      weight: "semibold"
    }))
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      margin: '0 16px',
      background: '#fff',
      borderRadius: 12,
      overflow: 'hidden'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '10px 16px 4px',
      fontSize: 12,
      color: '#8E8E93',
      letterSpacing: 0.4,
      textTransform: 'uppercase'
    }
  }, t('8 remotes · 3 chiffrés', '8 remotes · 3 encrypted')), REMOTES.map((r, i) => /*#__PURE__*/React.createElement(ListRow, {
    key: r.name,
    divider: i < REMOTES.length - 1,
    leading: /*#__PURE__*/React.createElement(BackendChip, {
      kind: r.chip,
      cryptOverlay: r.crypt
    }),
    title: /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("span", null, r.name), r.crypt && /*#__PURE__*/React.createElement(CryptBadge, null)),
    subtitle: t(r.sub.fr, r.sub.en),
    trailing: /*#__PURE__*/React.createElement(Icon, {
      name: "chevron.right",
      size: 14,
      weight: "semibold",
      style: {
        color: '#C7C7CC'
      }
    })
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(TabBar, {
    active: "remotes"
  }));
};
const FILES = [{
  name: {
    fr: 'Voyage Lisbonne 2024',
    en: 'Lisbon Trip 2024'
  },
  type: 'folder',
  sub: {
    fr: '142 éléments',
    en: '142 items'
  },
  state: null
}, {
  name: {
    fr: 'Archive impôts 2023',
    en: 'Tax Archive 2023'
  },
  type: 'folder',
  sub: {
    fr: '38 éléments',
    en: '38 items'
  },
  state: null
}, {
  name: {
    fr: 'Contrat-bail-2024.pdf',
    en: 'Lease-2024.pdf'
  },
  type: 'doc',
  sub: {
    fr: '2,4 Mo · PDF',
    en: '2.4 MB · PDF'
  },
  state: 'local'
}, {
  name: {
    fr: 'Présentation Q4.key',
    en: 'Q4-Presentation.key'
  },
  type: 'doc',
  sub: {
    fr: '18,7 Mo · Keynote',
    en: '18.7 MB · Keynote'
  },
  state: 'downloading',
  progress: 0.65
}, {
  name: {
    fr: 'IMG_4821.HEIC',
    en: 'IMG_4821.HEIC'
  },
  type: 'photo',
  sub: {
    fr: '4,1 Mo · HEIC',
    en: '4.1 MB · HEIC'
  },
  state: 'cloud'
}, {
  name: {
    fr: 'IMG_4822.HEIC',
    en: 'IMG_4822.HEIC'
  },
  type: 'photo',
  sub: {
    fr: '3,8 Mo · HEIC',
    en: '3.8 MB · HEIC'
  },
  state: 'cloud'
}, {
  name: {
    fr: 'sunset-timelapse.mov',
    en: 'sunset-timelapse.mov'
  },
  type: 'film',
  sub: {
    fr: '342 Mo · MOV',
    en: '342 MB · MOV'
  },
  state: 'cloud'
}, {
  name: {
    fr: 'piano-improv.m4a',
    en: 'piano-improv.m4a'
  },
  type: 'music',
  sub: {
    fr: '8,2 Mo · M4A',
    en: '8.2 MB · M4A'
  },
  state: 'local'
}, {
  name: {
    fr: 'rapport-annuel.docx',
    en: 'annual-report.docx'
  },
  type: 'doc',
  sub: {
    fr: '1,1 Mo · DOCX',
    en: '1.1 MB · DOCX'
  },
  state: 'syncing'
}];
const FileTypeIcon = ({
  type
}) => {
  const map = {
    folder: {
      icon: 'folder.fill',
      tint: '#1A73E8'
    },
    doc: {
      icon: 'doc',
      tint: '#8E8E93'
    },
    photo: {
      icon: 'photo',
      tint: '#FF2D55'
    },
    film: {
      icon: 'film',
      tint: '#AF52DE'
    },
    music: {
      icon: 'music',
      tint: '#FF9500'
    }
  };
  const m = map[type] || map.doc;
  return /*#__PURE__*/React.createElement("div", {
    style: {
      width: 36,
      height: 36,
      borderRadius: 9,
      background: m.tint + '20',
      color: m.tint,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: m.icon,
    size: 20,
    weight: "semibold"
  }));
};
const StateGlyph = ({
  state,
  progress
}) => {
  if (state === 'cloud') return /*#__PURE__*/React.createElement(Icon, {
    name: "cloud",
    size: 16,
    style: {
      color: '#8E8E93'
    }
  });
  if (state === 'local') return /*#__PURE__*/React.createElement(Icon, {
    name: "check.circle",
    size: 17,
    style: {
      color: '#34C759'
    }
  });
  if (state === 'syncing') return /*#__PURE__*/React.createElement(Icon, {
    name: "rotate",
    size: 16,
    weight: "semibold",
    style: {
      color: '#1A73E8'
    }
  });
  if (state === 'downloading') {
    const r = 8,
      c = 2 * Math.PI * r;
    return /*#__PURE__*/React.createElement("svg", {
      width: "20",
      height: "20",
      viewBox: "0 0 20 20"
    }, /*#__PURE__*/React.createElement("circle", {
      cx: "10",
      cy: "10",
      r: r,
      fill: "none",
      stroke: "rgba(60,60,67,0.25)",
      strokeWidth: "2"
    }), /*#__PURE__*/React.createElement("circle", {
      cx: "10",
      cy: "10",
      r: r,
      fill: "none",
      stroke: ACCENT,
      strokeWidth: "2",
      strokeDasharray: c,
      strokeDashoffset: c * (1 - progress),
      transform: "rotate(-90 10 10)",
      strokeLinecap: "round"
    }));
  }
  return null;
};
const ScreenFolder = () => {
  const t = useT();
  return /*#__PURE__*/React.createElement(ScreenFrame, {
    bg: "#F2F2F7"
  }, /*#__PURE__*/React.createElement(StatusBar, null), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '6px 16px 8px',
      display: 'flex',
      alignItems: 'center',
      gap: 6,
      color: ACCENT,
      fontSize: 16,
      fontWeight: 500
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "chevron.right",
    size: 16,
    weight: "semibold",
    style: {
      transform: 'rotate(180deg)'
    }
  }), /*#__PURE__*/React.createElement("span", null, "Remotes")), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '4px 20px 4px'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 8
    }
  }, /*#__PURE__*/React.createElement(BackendChip, {
    kind: "b2",
    cryptOverlay: true,
    size: 36
  }), /*#__PURE__*/React.createElement("h1", {
    style: {
      fontSize: 28,
      fontWeight: 700,
      letterSpacing: -0.5,
      margin: 0
    }
  }, "photos-archive")), /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 8,
      display: 'flex',
      alignItems: 'center',
      gap: 6,
      fontSize: 12,
      color: '#8E8E93',
      fontFamily: 'ui-monospace, "SF Mono", monospace'
    }
  }, /*#__PURE__*/React.createElement(CryptBadge, null), /*#__PURE__*/React.createElement("span", {
    style: {
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap'
    }
  }, "photos-archive:/2024/Lisbon"))), /*#__PURE__*/React.createElement("div", {
    style: {
      margin: '12px 16px 0',
      background: '#fff',
      borderRadius: 12,
      overflow: 'hidden'
    }
  }, FILES.map((f, i) => /*#__PURE__*/React.createElement(ListRow, {
    key: f.name.en,
    divider: i < FILES.length - 1,
    leading: /*#__PURE__*/React.createElement(FileTypeIcon, {
      type: f.type
    }),
    title: t(f.name.fr, f.name.en),
    subtitle: t(f.sub.fr, f.sub.en),
    trailing: /*#__PURE__*/React.createElement("div", {
      style: {
        display: 'flex',
        alignItems: 'center',
        gap: 10
      }
    }, /*#__PURE__*/React.createElement(StateGlyph, {
      state: f.state,
      progress: f.progress
    }), /*#__PURE__*/React.createElement(Icon, {
      name: "chevron.right",
      size: 14,
      weight: "semibold",
      style: {
        color: '#C7C7CC'
      }
    }))
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(TabBar, {
    active: "remotes"
  }));
};
const ScreenFileDetail = () => {
  const t = useT();
  return /*#__PURE__*/React.createElement(ScreenFrame, {
    bg: "#F2F2F7"
  }, /*#__PURE__*/React.createElement(StatusBar, null), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '6px 16px 8px',
      display: 'flex',
      alignItems: 'center',
      gap: 6,
      color: ACCENT,
      fontSize: 16,
      fontWeight: 500
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "chevron.right",
    size: 16,
    weight: "semibold",
    style: {
      transform: 'rotate(180deg)'
    }
  }), /*#__PURE__*/React.createElement("span", null, t('Lisbonne', 'Lisbon'))), /*#__PURE__*/React.createElement("div", {
    style: {
      margin: '4px 16px 0',
      borderRadius: 16,
      overflow: 'hidden',
      position: 'relative',
      aspectRatio: '4/3'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      inset: 0,
      background: 'linear-gradient(135deg, #FFB088 0%, #FF6B6B 35%, #C44569 100%)'
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      inset: 0,
      background: 'radial-gradient(ellipse at 30% 80%, rgba(255,200,100,0.5), transparent 60%)'
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      bottom: 0,
      left: 0,
      right: 0,
      height: '40%',
      background: 'linear-gradient(transparent, rgba(0,0,0,0.45))'
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      bottom: 12,
      left: 14,
      right: 14,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      color: '#fff'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 13,
      fontWeight: 600
    }
  }, "sunset-belem.jpg"), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '4px 8px',
      background: 'rgba(255,255,255,0.22)',
      backdropFilter: 'blur(10px)',
      borderRadius: 6,
      fontSize: 11,
      fontWeight: 700,
      letterSpacing: 0.4
    }
  }, "4032 × 3024"))), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '14px 20px 4px'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 8,
      flexWrap: 'wrap'
    }
  }, /*#__PURE__*/React.createElement("h1", {
    style: {
      fontSize: 24,
      fontWeight: 700,
      margin: 0,
      letterSpacing: -0.4
    }
  }, "sunset-belem.jpg"), /*#__PURE__*/React.createElement(CryptBadge, null)), /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 4,
      fontSize: 13,
      color: '#8E8E93'
    }
  }, t('4,1 Mo · HEIC · modifié il y a 2h', '4.1 MB · HEIC · edited 2h ago'))), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '16px 16px 0',
      display: 'grid',
      gridTemplateColumns: 'repeat(4, 1fr)',
      gap: 8
    }
  }, [{
    title: t('Ouvrir', 'Open'),
    icon: 'play.fill',
    primary: true
  }, {
    title: t('Télécharger', 'Download'),
    icon: 'download',
    primary: false
  }, {
    title: t('Partager', 'Share'),
    icon: 'share',
    primary: false
  }, {
    title: t('Favori', 'Favorite'),
    icon: 'star.fill',
    primary: false
  }].map(a => /*#__PURE__*/React.createElement("button", {
    key: a.title,
    style: {
      padding: '14px 6px 12px',
      borderRadius: 12,
      background: a.primary ? ACCENT : 'rgba(255,255,255,0.85)',
      color: a.primary ? '#fff' : ACCENT,
      border: a.primary ? 'none' : '0.5px solid rgba(60,60,67,0.18)',
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      gap: 6,
      boxShadow: a.primary ? `0 4px 12px ${ACCENT}40` : 'none'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: a.icon,
    size: 22,
    weight: "semibold"
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 11,
      fontWeight: 600,
      color: a.primary ? '#fff' : '#000'
    }
  }, a.title)))), /*#__PURE__*/React.createElement("div", {
    style: {
      margin: '16px 16px 0',
      background: '#fff',
      borderRadius: 12,
      padding: '14px 16px'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 12,
      color: '#8E8E93',
      letterSpacing: 0.4,
      textTransform: 'uppercase',
      marginBottom: 8
    }
  }, t('Sécurité & intégrité', 'Security & integrity')), [{
    k: t('Chiffrement', 'Encryption'),
    v: 'NaCl secretbox (XSalsa20-Poly1305)'
  }, {
    k: 'SHA-256',
    v: '7f3a · b2d8 · 9e1c · 4a52',
    mono: true
  }, {
    k: t('Stockage', 'Storage'),
    v: 'b2://photos-archive-crypt/2024…'
  }, {
    k: 'TLS',
    v: t('TLS 1.3 · ATS strict', 'TLS 1.3 · strict ATS'),
    last: true
  }].map(r => /*#__PURE__*/React.createElement("div", {
    key: r.k,
    style: {
      display: 'flex',
      justifyContent: 'space-between',
      alignItems: 'center',
      padding: '6px 0',
      borderBottom: r.last ? 'none' : '0.5px solid rgba(60,60,67,0.12)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 14,
      color: '#8E8E93'
    }
  }, r.k), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 13,
      color: '#000',
      textAlign: 'right',
      fontFamily: r.mono ? 'ui-monospace, "SF Mono", monospace' : 'inherit'
    }
  }, r.v)))), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(TabBar, {
    active: "remotes"
  }));
};
const ScreenHome = () => {
  const t = useT();
  return /*#__PURE__*/React.createElement(ScreenFrame, {
    bg: "#F2F2F7"
  }, /*#__PURE__*/React.createElement(StatusBar, null), /*#__PURE__*/React.createElement(NavHeader, {
    title: t('Accueil', 'Home'),
    trailing: /*#__PURE__*/React.createElement(Icon, {
      name: "rotate",
      size: 22,
      weight: "semibold",
      style: {
        color: ACCENT,
        paddingBottom: 8
      }
    })
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      margin: '0 16px',
      borderRadius: 16,
      padding: 18,
      background: `linear-gradient(135deg, ${ACCENT} 0%, ${ACCENT_DEEP} 100%)`,
      color: '#fff',
      boxShadow: `0 10px 24px ${ACCENT}40`
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 10
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: 36,
      height: 36,
      borderRadius: 10,
      background: 'rgba(255,255,255,0.18)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "bolt.fill",
    size: 20
  })), /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 18,
      fontWeight: 700
    }
  }, t('Transferts en cours', 'Active transfers')), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 13,
      opacity: 0.9,
      marginTop: 1
    }
  }, t('3 opérations actives sur 8 remotes', '3 active operations across 8 remotes')))), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'grid',
      gridTemplateColumns: 'repeat(2, 1fr)',
      gap: 8,
      marginTop: 14
    }
  }, [{
    v: '8',
    l: t('remotes', 'remotes'),
    i: 'externaldrive'
  }, {
    v: '3',
    l: t('actifs', 'active'),
    i: 'bolt.fill'
  }, {
    v: '142',
    l: t('photos sync', 'photos sync'),
    i: 'photo'
  }, {
    v: t('4,2 Go', '4.2 GB'),
    l: t('cache', 'cache'),
    i: 'tray'
  }].map(m => /*#__PURE__*/React.createElement("div", {
    key: m.l,
    style: {
      background: 'rgba(255,255,255,0.14)',
      borderRadius: 10,
      padding: '10px 12px',
      display: 'flex',
      alignItems: 'center',
      gap: 10
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: m.i,
    size: 18
  }), /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 18,
      fontWeight: 700
    }
  }, m.v), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 11,
      opacity: 0.85
    }
  }, m.l)))))), /*#__PURE__*/React.createElement("div", {
    style: {
      margin: '18px 16px 0'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 13,
      color: '#8E8E93',
      letterSpacing: 0.4,
      textTransform: 'uppercase',
      padding: '0 4px 8px'
    }
  }, t('Actions rapides', 'Quick actions')), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'grid',
      gridTemplateColumns: 'repeat(3, 1fr)',
      gap: 10
    }
  }, [{
    t: t('Nouveau', 'New'),
    s: t('Ajouter remote', 'Add remote'),
    i: 'plus.circle',
    c: '#1A73E8'
  }, {
    t: t('Importer', 'Import'),
    s: 'rclone.conf',
    i: 'download',
    c: '#34C759'
  }, {
    t: t('Photos', 'Photos'),
    s: t('142 en attente', '142 pending'),
    i: 'photo.stack',
    c: '#FF2D55'
  }].map(a => /*#__PURE__*/React.createElement("div", {
    key: a.t,
    style: {
      background: '#fff',
      borderRadius: 12,
      padding: 12,
      border: '0.5px solid rgba(60,60,67,0.1)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: 32,
      height: 32,
      borderRadius: 8,
      background: a.c + '22',
      color: a.c,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: a.i,
    size: 18,
    weight: "semibold"
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 8,
      fontSize: 14,
      fontWeight: 600
    }
  }, a.t), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 11,
      color: '#8E8E93',
      marginTop: 1
    }
  }, a.s))))), /*#__PURE__*/React.createElement("div", {
    style: {
      margin: '18px 16px 0'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 13,
      color: '#8E8E93',
      letterSpacing: 0.4,
      textTransform: 'uppercase',
      padding: '0 4px 8px'
    }
  }, t('Récents', 'Recents')), /*#__PURE__*/React.createElement("div", {
    style: {
      background: '#fff',
      borderRadius: 12,
      overflow: 'hidden'
    }
  }, [{
    n: t('Voyage Lisbonne 2024', 'Lisbon Trip 2024'),
    s: 'photos-archive',
    tm: t('il y a 3 min', '3 min ago'),
    chip: 'b2',
    crypt: true
  }, {
    n: t('Présentation Q4', 'Q4 Presentation'),
    s: 'work-drive',
    tm: t('il y a 1 h', '1 h ago'),
    chip: 'drive',
    crypt: false
  }, {
    n: t('Backups système', 'System backups'),
    s: 'backups-r2',
    tm: t('hier', 'yesterday'),
    chip: 's3',
    crypt: true
  }].map((r, i, arr) => /*#__PURE__*/React.createElement(ListRow, {
    key: r.n,
    divider: i < arr.length - 1,
    leading: /*#__PURE__*/React.createElement(BackendChip, {
      kind: r.chip,
      cryptOverlay: r.crypt,
      size: 32
    }),
    title: r.n,
    subtitle: r.s,
    trailing: /*#__PURE__*/React.createElement("span", {
      style: {
        fontSize: 12,
        color: '#8E8E93'
      }
    }, r.tm)
  })))), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(TabBar, {
    active: "home"
  }));
};
const WIZARD_BACKENDS = [{
  k: 's3',
  label: 'Amazon S3'
}, {
  k: 'b2',
  label: 'Backblaze B2'
}, {
  k: 'drive',
  label: 'Google Drive'
}, {
  k: 'dropbox',
  label: 'Dropbox'
}, {
  k: 'onedrive',
  label: 'OneDrive'
}, {
  k: 'box',
  label: 'Box'
}, {
  k: 'sftp',
  label: 'SFTP'
}, {
  k: 'webdav',
  label: 'WebDAV'
}, {
  k: 'crypt',
  label: 'Crypt'
}, {
  k: 'storj',
  label: 'Storj DCS'
}, {
  k: 'wasabi',
  label: 'Wasabi'
}, {
  k: 'pcloud',
  label: 'pCloud'
}];
const ScreenWizard = () => {
  const t = useT();
  return /*#__PURE__*/React.createElement(ScreenFrame, {
    bg: "#F2F2F7"
  }, /*#__PURE__*/React.createElement(StatusBar, null), /*#__PURE__*/React.createElement("div", {
    style: {
      height: 22,
      display: 'flex',
      justifyContent: 'center',
      alignItems: 'flex-end',
      paddingBottom: 8
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: 36,
      height: 5,
      borderRadius: 3,
      background: 'rgba(60,60,67,0.3)'
    }
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      justifyContent: 'space-between',
      padding: '0 16px 4px',
      color: ACCENT,
      fontSize: 16
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontWeight: 500
    }
  }, t('Annuler', 'Cancel')), /*#__PURE__*/React.createElement("span", {
    style: {
      fontWeight: 600,
      color: '#000',
      fontSize: 17
    }
  }, t('Nouveau remote', 'New remote')), /*#__PURE__*/React.createElement("span", {
    style: {
      opacity: 0.4
    }
  }, t('Suivant', 'Next'))), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '14px 20px 0',
      display: 'flex',
      alignItems: 'center',
      gap: 6
    }
  }, [1, 2, 3, 4].map(s => /*#__PURE__*/React.createElement("div", {
    key: s,
    style: {
      flex: 1,
      height: 4,
      borderRadius: 2,
      background: s === 1 ? ACCENT : 'rgba(60,60,67,0.18)'
    }
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '10px 20px 0',
      fontSize: 12,
      color: '#8E8E93',
      letterSpacing: 0.4,
      textTransform: 'uppercase'
    }
  }, t('Étape 1 sur 4 — Choisir un backend', 'Step 1 of 4 — Choose a backend')), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '12px 20px 0'
    }
  }, /*#__PURE__*/React.createElement("h2", {
    style: {
      fontSize: 22,
      fontWeight: 700,
      margin: 0,
      letterSpacing: -0.4
    }
  }, t('Quel stockage veux-tu connecter ?', 'Which storage do you want to connect?')), /*#__PURE__*/React.createElement("p", {
    style: {
      fontSize: 14,
      color: '#8E8E93',
      marginTop: 4
    }
  }, t('70+ services pris en charge. OAuth en 2 tapotements.', '70+ services supported. OAuth in 2 taps.'))), /*#__PURE__*/React.createElement("div", {
    style: {
      margin: '14px 20px 0',
      display: 'flex',
      alignItems: 'center',
      gap: 8,
      background: 'rgba(118,118,128,0.12)',
      borderRadius: 10,
      padding: '8px 12px'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "magnifying",
    size: 16,
    style: {
      color: '#8E8E93'
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 15,
      color: '#8E8E93'
    }
  }, t('Rechercher un backend', 'Search a backend'))), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '14px 20px 0',
      display: 'grid',
      gridTemplateColumns: 'repeat(3, 1fr)',
      gap: 10
    }
  }, WIZARD_BACKENDS.map(b => /*#__PURE__*/React.createElement("div", {
    key: b.k,
    style: {
      background: '#fff',
      borderRadius: 14,
      padding: '14px 8px',
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      gap: 8,
      border: b.k === 'crypt' ? `1.5px solid ${ACCENT}` : '0.5px solid rgba(60,60,67,0.1)',
      boxShadow: b.k === 'crypt' ? `0 4px 14px ${ACCENT}25` : 'none'
    }
  }, /*#__PURE__*/React.createElement(BackendChip, {
    kind: b.k,
    size: 44
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 12,
      fontWeight: 600,
      textAlign: 'center',
      lineHeight: 1.2
    }
  }, b.label), b.k === 'crypt' && /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'relative',
      marginTop: -4,
      fontSize: 9,
      fontWeight: 700,
      letterSpacing: 0.4,
      color: ACCENT,
      padding: '2px 6px',
      background: ACCENT_SOFT,
      borderRadius: 4
    }
  }, t('RECOMMANDÉ', 'RECOMMENDED'))))), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 20px 28px'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 12,
      color: '#8E8E93',
      textAlign: 'center'
    }
  }, t('Ou ', 'Or '), /*#__PURE__*/React.createElement("span", {
    style: {
      color: ACCENT,
      fontWeight: 600
    }
  }, t('importer un rclone.conf existant', 'import an existing rclone.conf')))));
};
const ScreenPhotoSync = () => {
  const t = useT();
  return /*#__PURE__*/React.createElement(ScreenFrame, {
    bg: "#F2F2F7"
  }, /*#__PURE__*/React.createElement(StatusBar, null), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '6px 16px 8px',
      display: 'flex',
      alignItems: 'center',
      gap: 6,
      color: ACCENT,
      fontSize: 16,
      fontWeight: 500
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "chevron.right",
    size: 16,
    weight: "semibold",
    style: {
      transform: 'rotate(180deg)'
    }
  }), /*#__PURE__*/React.createElement("span", null, t('Réglages', 'Settings'))), /*#__PURE__*/React.createElement(NavHeader, {
    title: t('Sync Photos', 'Photo Sync'),
    trailing: null
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      margin: '0 16px',
      borderRadius: 16,
      padding: 16,
      background: 'linear-gradient(135deg, #FF2D55 0%, #C44569 100%)',
      color: '#fff',
      boxShadow: '0 10px 24px rgba(255,45,85,0.30)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 12
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "photo.stack",
    size: 28
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 16,
      fontWeight: 700
    }
  }, t('Sauvegarde active', 'Backup active')), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 12,
      opacity: 0.9,
      marginTop: 1
    }
  }, t('Vers photos-archive · chiffré', 'To photos-archive · encrypted'))), /*#__PURE__*/React.createElement("div", {
    style: {
      width: 48,
      height: 28,
      borderRadius: 14,
      background: 'rgba(255,255,255,0.35)',
      padding: 2,
      display: 'flex',
      justifyContent: 'flex-end'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: 24,
      height: 24,
      borderRadius: '50%',
      background: '#fff'
    }
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 16
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      justifyContent: 'space-between',
      fontSize: 12,
      marginBottom: 6
    }
  }, /*#__PURE__*/React.createElement("span", null, t('2 418 / 2 560 médias', '2,418 / 2,560 items')), /*#__PURE__*/React.createElement("span", {
    style: {
      fontWeight: 600
    }
  }, "94 %")), /*#__PURE__*/React.createElement("div", {
    style: {
      height: 6,
      borderRadius: 3,
      background: 'rgba(255,255,255,0.25)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: '94%',
      height: '100%',
      borderRadius: 3,
      background: '#fff'
    }
  })))), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '14px 16px 0',
      display: 'grid',
      gridTemplateColumns: 'repeat(3, 1fr)',
      gap: 8
    }
  }, [{
    v: '2 418',
    l: t('sauvegardées', 'backed up'),
    i: 'check.circle',
    c: '#34C759'
  }, {
    v: '142',
    l: t('en attente', 'pending'),
    i: 'clock',
    c: '#FF9500'
  }, {
    v: t('38 Go', '38 GB'),
    l: t('transférés', 'transferred'),
    i: 'arrow.up',
    c: '#1A73E8'
  }].map(s => /*#__PURE__*/React.createElement("div", {
    key: s.l,
    style: {
      background: '#fff',
      borderRadius: 12,
      padding: 12
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: s.i,
    size: 18,
    style: {
      color: s.c
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 18,
      fontWeight: 700,
      marginTop: 6
    }
  }, s.v), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 11,
      color: '#8E8E93',
      marginTop: 1
    }
  }, s.l)))), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '8px 16px 0',
      fontSize: 13,
      color: '#8E8E93',
      letterSpacing: 0.4,
      textTransform: 'uppercase',
      marginTop: 14
    }
  }, t('Conditions', 'Conditions')), /*#__PURE__*/React.createElement("div", {
    style: {
      margin: '6px 16px 0',
      background: '#fff',
      borderRadius: 12,
      overflow: 'hidden'
    }
  }, [{
    i: 'wifi',
    t: t('Wi-Fi uniquement', 'Wi-Fi only'),
    s: t('Pas de cellulaire', 'No cellular'),
    on: true
  }, {
    i: 'bolt.fill',
    t: t('Charger en priorité', 'Charge priority'),
    s: t('Quand branché', 'When plugged in'),
    on: true
  }, {
    i: 'speedometer',
    t: t('Débit adaptatif', 'Adaptive throughput'),
    s: t('8 Mo/s actif · 80 Mo/s veille', '8 MB/s active · 80 MB/s idle'),
    on: true
  }].map((opt, i, arr) => /*#__PURE__*/React.createElement(ListRow, {
    key: opt.t,
    divider: i < arr.length - 1,
    leading: /*#__PURE__*/React.createElement("div", {
      style: {
        width: 30,
        height: 30,
        borderRadius: 8,
        background: ACCENT_SOFT,
        color: ACCENT,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center'
      }
    }, /*#__PURE__*/React.createElement(Icon, {
      name: opt.i,
      size: 16,
      weight: "semibold"
    })),
    title: opt.t,
    subtitle: opt.s,
    trailing: /*#__PURE__*/React.createElement("div", {
      style: {
        width: 50,
        height: 30,
        borderRadius: 15,
        background: opt.on ? '#34C759' : '#E5E5EA',
        padding: 2,
        display: 'flex',
        justifyContent: opt.on ? 'flex-end' : 'flex-start'
      }
    }, /*#__PURE__*/React.createElement("div", {
      style: {
        width: 26,
        height: 26,
        borderRadius: '50%',
        background: '#fff',
        boxShadow: '0 2px 4px rgba(0,0,0,0.2)'
      }
    }))
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(TabBar, {
    active: "settings"
  }));
};
const ScreenSecurity = () => {
  const t = useT();
  return /*#__PURE__*/React.createElement(ScreenFrame, {
    bg: "#F2F2F7"
  }, /*#__PURE__*/React.createElement(StatusBar, null), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '6px 16px 8px',
      display: 'flex',
      alignItems: 'center',
      gap: 6,
      color: ACCENT,
      fontSize: 16,
      fontWeight: 500
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "chevron.right",
    size: 16,
    weight: "semibold",
    style: {
      transform: 'rotate(180deg)'
    }
  }), /*#__PURE__*/React.createElement("span", null, t('Réglages', 'Settings'))), /*#__PURE__*/React.createElement(NavHeader, {
    title: t('Sécurité', 'Security')
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '4px 24px 0',
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      textAlign: 'center'
    }
  }, /*#__PURE__*/React.createElement(CryptSeal, {
    size: 104
  }), /*#__PURE__*/React.createElement("h2", {
    style: {
      fontSize: 22,
      fontWeight: 700,
      margin: '20px 0 6px',
      letterSpacing: -0.3
    }
  }, t('Tes clés ne quittent pas l\'iPhone', 'Your keys never leave the iPhone')), /*#__PURE__*/React.createElement("p", {
    style: {
      fontSize: 14,
      color: '#3C3C43',
      margin: 0,
      maxWidth: 320,
      lineHeight: 1.4
    }
  }, t('Configuration chiffrée au repos · ChaCha20-Poly1305 · OAuth dans le Trousseau iOS.', 'Config encrypted at rest · ChaCha20-Poly1305 · OAuth in the iOS Keychain.'))), /*#__PURE__*/React.createElement("div", {
    style: {
      margin: '20px 16px 0',
      background: '#fff',
      borderRadius: 12,
      overflow: 'hidden'
    }
  }, [{
    i: 'faceid',
    t: 'Face ID',
    s: t('Verrouiller au lancement', 'Lock on launch'),
    on: true
  }, {
    i: 'lock.fill',
    t: t('Verrouillage immédiat', 'Instant lock'),
    s: t('Dès retour à l\'écran d\'accueil', 'On return to Home Screen'),
    on: true
  }, {
    i: 'key',
    t: t('Trousseau iOS', 'iOS Keychain'),
    s: t('4 jetons OAuth protégés', '4 protected OAuth tokens'),
    chev: true
  }].map((opt, i, arr) => /*#__PURE__*/React.createElement(ListRow, {
    key: opt.t,
    divider: i < arr.length - 1,
    leading: /*#__PURE__*/React.createElement("div", {
      style: {
        width: 30,
        height: 30,
        borderRadius: 8,
        background: ACCENT_SOFT,
        color: ACCENT,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center'
      }
    }, /*#__PURE__*/React.createElement(Icon, {
      name: opt.i,
      size: 16,
      weight: "semibold"
    })),
    title: opt.t,
    subtitle: opt.s,
    trailing: opt.chev ? /*#__PURE__*/React.createElement(Icon, {
      name: "chevron.right",
      size: 14,
      weight: "semibold",
      style: {
        color: '#C7C7CC'
      }
    }) : /*#__PURE__*/React.createElement("div", {
      style: {
        width: 50,
        height: 30,
        borderRadius: 15,
        background: opt.on ? '#34C759' : '#E5E5EA',
        padding: 2,
        display: 'flex',
        justifyContent: opt.on ? 'flex-end' : 'flex-start'
      }
    }, /*#__PURE__*/React.createElement("div", {
      style: {
        width: 26,
        height: 26,
        borderRadius: '50%',
        background: '#fff',
        boxShadow: '0 2px 4px rgba(0,0,0,0.2)'
      }
    }))
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '20px 16px 0',
      fontSize: 13,
      color: '#8E8E93',
      letterSpacing: 0.4,
      textTransform: 'uppercase'
    }
  }, t('Garanties confidentialité', 'Privacy guarantees')), /*#__PURE__*/React.createElement("div", {
    style: {
      margin: '6px 16px 0',
      background: '#fff',
      borderRadius: 12,
      padding: '6px 14px'
    }
  }, [t('Aucune analytics, aucun tracker', 'No analytics, no trackers'), t('Aucun serveur backend tiers', 'No third-party backend server'), t('ATS strict — TLS 1.3 partout', 'Strict ATS — TLS 1.3 everywhere'), t('Open source · auditable sur GitHub', 'Open source · auditable on GitHub')].map((line, i, arr) => /*#__PURE__*/React.createElement("div", {
    key: line,
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 12,
      padding: '12px 0',
      borderBottom: i < arr.length - 1 ? '0.5px solid rgba(60,60,67,0.12)' : 'none'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "check.circle",
    size: 20,
    style: {
      color: '#34C759'
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 15
    }
  }, line)))), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(TabBar, {
    active: "settings"
  }));
};

/* ─── v1.5 : Galerie en grille ─────────────────────────────────────── */
const GALLERY_TILES = [{
  v: false,
  g: 'linear-gradient(135deg,#FFB088,#C44569)'
}, {
  v: true,
  g: 'linear-gradient(135deg,#6C7BFF,#241452)',
  d: '1:24'
}, {
  v: false,
  g: 'linear-gradient(135deg,#34C759,#0E7A3A)'
}, {
  v: false,
  g: 'linear-gradient(135deg,#0E5FAE,#093E70)'
}, {
  v: true,
  g: 'linear-gradient(135deg,#FF2D55,#7A0E2A)',
  d: '0:42'
}, {
  v: false,
  g: 'linear-gradient(135deg,#FF9500,#A85E00)'
}, {
  v: false,
  g: 'linear-gradient(135deg,#AF52DE,#5B21B6)'
}, {
  v: true,
  g: 'linear-gradient(135deg,#16A085,#0B5345)',
  d: '3:08'
}, {
  v: false,
  g: 'linear-gradient(135deg,#FFD16B,#C98A00)'
}, {
  v: false,
  g: 'linear-gradient(135deg,#FF6B6B,#8A2842)'
}, {
  v: true,
  g: 'linear-gradient(135deg,#5AC8FA,#0E5FAE)',
  d: '0:18'
}, {
  v: false,
  g: 'linear-gradient(135deg,#BF5AF2,#6B1FB0)'
}];
const Segmented = ({
  active
}) => {
  const items = [{
    id: 'list',
    icon: 'tray'
  }, {
    id: 'grid',
    icon: 'photo.stack'
  }];
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'inline-flex',
      background: 'rgba(118,118,128,0.16)',
      borderRadius: 9,
      padding: 2
    }
  }, items.map(it => /*#__PURE__*/React.createElement("div", {
    key: it.id,
    style: {
      width: 38,
      height: 30,
      borderRadius: 7,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      background: it.id === active ? '#fff' : 'transparent',
      color: it.id === active ? ACCENT : '#8E8E93',
      boxShadow: it.id === active ? '0 1px 3px rgba(0,0,0,0.18)' : 'none'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: it.icon,
    size: 17,
    weight: "semibold"
  }))));
};
const ScreenGallery = () => {
  const t = useT();
  return /*#__PURE__*/React.createElement(ScreenFrame, {
    bg: "#F2F2F7"
  }, /*#__PURE__*/React.createElement(StatusBar, null), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '6px 16px 8px',
      display: 'flex',
      alignItems: 'center',
      gap: 6,
      color: ACCENT,
      fontSize: 16,
      fontWeight: 500
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "chevron.right",
    size: 16,
    weight: "semibold",
    style: {
      transform: 'rotate(180deg)'
    }
  }), /*#__PURE__*/React.createElement("span", null, "Remotes")), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '2px 20px 0',
      display: 'flex',
      alignItems: 'flex-end',
      justifyContent: 'space-between'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 8
    }
  }, /*#__PURE__*/React.createElement(BackendChip, {
    kind: "b2",
    cryptOverlay: true,
    size: 34
  }), /*#__PURE__*/React.createElement("h1", {
    style: {
      fontSize: 26,
      fontWeight: 700,
      letterSpacing: -0.5,
      margin: 0
    }
  }, t('Galerie', 'Gallery'))), /*#__PURE__*/React.createElement("div", {
    style: {
      paddingBottom: 4
    }
  }, /*#__PURE__*/React.createElement(Segmented, {
    active: "grid"
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '10px 16px 0',
      display: 'flex',
      alignItems: 'center',
      gap: 8
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: 6,
      background: ACCENT,
      color: '#fff',
      padding: '6px 12px',
      borderRadius: 999,
      fontSize: 13,
      fontWeight: 700
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "photo.stack",
    size: 14,
    weight: "bold"
  }), t('Médias uniquement', 'Media only')), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 13,
      color: '#8E8E93',
      fontWeight: 500
    }
  }, t('86 photos · 12 vidéos', '86 photos · 12 videos'))), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '12px 16px 0',
      display: 'grid',
      gridTemplateColumns: 'repeat(3, 1fr)',
      gap: 6
    }
  }, GALLERY_TILES.map((tile, i) => /*#__PURE__*/React.createElement("div", {
    key: i,
    style: {
      position: 'relative',
      aspectRatio: '1/1',
      borderRadius: 10,
      overflow: 'hidden',
      background: tile.g
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      inset: 0,
      background: 'radial-gradient(ellipse at 30% 20%, rgba(255,255,255,0.25), transparent 55%)'
    }
  }), tile.v && /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      top: 6,
      left: 6,
      width: 22,
      height: 22,
      borderRadius: '50%',
      background: 'rgba(0,0,0,0.42)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      color: '#fff'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "play.fill",
    size: 10
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      bottom: 5,
      right: 6,
      fontSize: 10,
      fontWeight: 700,
      color: '#fff',
      textShadow: '0 1px 3px rgba(0,0,0,0.5)'
    }
  }, tile.d))))), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(TabBar, {
    active: "remotes"
  }));
};

/* ─── v1.5 : Lecteur vidéo intégré ─────────────────────────────────── */
const ScreenPlayer = () => {
  const t = useT();
  return /*#__PURE__*/React.createElement(ScreenFrame, {
    bg: "#0A0A0F"
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      inset: 0,
      background: 'linear-gradient(160deg, #3A2A6E 0%, #1A1030 52%, #0A0A0F 100%)'
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      inset: 0,
      background: 'radial-gradient(ellipse at 50% 36%, rgba(124,58,237,0.5), transparent 62%)'
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'relative',
      padding: '56px 22px 0',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      color: '#fff'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 16,
      fontWeight: 600
    }
  }, t('OK', 'Done')), /*#__PURE__*/React.createElement("div", {
    style: {
      textAlign: 'center',
      minWidth: 0,
      flex: 1,
      padding: '0 12px'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 15,
      fontWeight: 600,
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      whiteSpace: 'nowrap'
    }
  }, "sunset-timelapse.mkv"), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 11,
      opacity: 0.7,
      marginTop: 2
    }
  }, t('media · Crypt sur B2', 'media · Crypt on B2'))), /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 11,
      fontWeight: 800,
      letterSpacing: 0.6,
      padding: '4px 8px',
      borderRadius: 6,
      background: 'rgba(255,255,255,0.18)'
    }
  }, "VLC")), /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'relative',
      flex: 1,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      gap: 34,
      color: '#fff'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      opacity: 0.85
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "rotate",
    size: 26,
    weight: "semibold",
    style: {
      transform: 'scaleX(-1)'
    }
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      width: 84,
      height: 84,
      borderRadius: '50%',
      background: 'rgba(255,255,255,0.16)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      border: '1px solid rgba(255,255,255,0.25)'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "play.fill",
    size: 36
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      opacity: 0.85
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "rotate",
    size: 26,
    weight: "semibold"
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'relative',
      display: 'flex',
      justifyContent: 'center',
      paddingBottom: 14
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: 7,
      background: 'rgba(255,255,255,0.16)',
      color: '#fff',
      padding: '8px 14px',
      borderRadius: 999,
      fontSize: 13,
      fontWeight: 600
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "clock",
    size: 14
  }), t('Reprendre à 12:34', 'Resume at 12:34'))), /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'relative',
      padding: '0 22px 40px',
      color: '#fff'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      height: 5,
      borderRadius: 3,
      background: 'rgba(255,255,255,0.25)',
      position: 'relative'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: '42%',
      height: '100%',
      borderRadius: 3,
      background: '#fff'
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      left: '42%',
      top: '50%',
      transform: 'translate(-50%,-50%)',
      width: 13,
      height: 13,
      borderRadius: '50%',
      background: '#fff',
      boxShadow: '0 2px 6px rgba(0,0,0,0.4)'
    }
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      justifyContent: 'space-between',
      fontSize: 12,
      opacity: 0.85,
      marginTop: 7
    }
  }, /*#__PURE__*/React.createElement("span", null, "12:34"), /*#__PURE__*/React.createElement("span", null, "-27:46")), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      justifyContent: 'space-between',
      alignItems: 'center',
      marginTop: 18
    }
  }, [{
    icon: 'doc',
    label: t('Sous-titres', 'Subtitles')
  }, {
    icon: 'music',
    label: t('Audio', 'Audio')
  }, {
    icon: 'speedometer',
    label: '1.0×'
  }, {
    icon: 'share',
    label: t('Externe', 'External')
  }].map(b => /*#__PURE__*/React.createElement("div", {
    key: b.label,
    style: {
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      gap: 5,
      opacity: 0.92
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: b.icon,
    size: 20,
    weight: "semibold"
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 10,
      fontWeight: 600
    }
  }, b.label))))));
};

/* ════════════════════════════════════════════════════════════════════
   Shots (palettes + headlines repris de app.jsx)
   ════════════════════════════════════════════════════════════════════ */
const PALETTES = {
  violet: {
    from: '#F4EEFE',
    to: '#E8DCFA',
    accent: ACCENT,
    deep: ACCENT_DEEP
  },
  cream: {
    from: '#FBF7EE',
    to: '#F2E7CC',
    accent: '#7C3AED',
    deep: '#5B21B6'
  },
  midnight: {
    from: '#1A1530',
    to: '#0E0820',
    accent: '#A78BFA',
    deep: '#7C3AED',
    dark: true
  },
  ocean: {
    from: '#E6F0FB',
    to: '#CFE0F4',
    accent: '#0E5FAE',
    deep: '#093E70'
  },
  forest: {
    from: '#E7F2EC',
    to: '#CFE5D7',
    accent: '#1F8F4A',
    deep: '#136230'
  },
  rose: {
    from: '#FBECEF',
    to: '#F4D5DC',
    accent: '#C44569',
    deep: '#8A2842'
  }
};
const SHOTS = [{
  id: 'crypt-first',
  Screen: ScreenOnboarding,
  palette: 'violet',
  fr: {
    h: 'Tous vos clouds.\nChiffrés.',
    s: 'rclone crypt natif. Vos clés ne quittent jamais l\'iPhone.'
  },
  en: {
    h: 'Every cloud.\nEncrypted.',
    s: 'Native rclone crypt. Your keys never leave the iPhone.'
  }
}, {
  id: 'backends',
  Screen: ScreenRemotes,
  palette: 'ocean',
  fr: {
    h: '80+ services.\nUn seul endroit.',
    s: 'S3, R2, Drive, Dropbox, B2, SFTP, WebDAV, Storj, Wasabi…'
  },
  en: {
    h: '80+ services.\nOne home.',
    s: 'S3, R2, Drive, Dropbox, B2, SFTP, WebDAV, Storj, Wasabi…'
  }
}, {
  id: 'crypt-paths',
  Screen: ScreenFolder,
  palette: 'violet',
  fr: {
    h: 'Noms déchiffrés\nà la volée.',
    s: 'Aucun transit en clair. AES-256 + NaCl secretbox.'
  },
  en: {
    h: 'Filenames decrypted\non the fly.',
    s: 'No cleartext in transit. AES-256 + NaCl secretbox.'
  }
}, {
  id: 'stream',
  Screen: ScreenFileDetail,
  palette: 'rose',
  fr: {
    h: 'Stream direct.\nZéro téléchargement.',
    s: 'Photos, vidéos, PDF — ouverts depuis Fichiers iOS.'
  },
  en: {
    h: 'Stream direct.\nNo full download.',
    s: 'Photos, video, PDF — opened straight from Files.'
  }
}, {
  id: 'player',
  Screen: ScreenPlayer,
  palette: 'midnight',
  isNew: true,
  fr: {
    h: 'Lecteur vidéo\nintégré.',
    s: 'MKV, AVI, WebM, TS… Sous-titres, pistes audio, reprise. Dans l\'app ou en externe.'
  },
  en: {
    h: 'Built-in\nvideo player.',
    s: 'MKV, AVI, WebM, TS… Subtitles, audio tracks, resume. In-app or external.'
  }
}, {
  id: 'gallery',
  Screen: ScreenGallery,
  palette: 'forest',
  isNew: true,
  fr: {
    h: 'Une vraie\ngalerie médias.',
    s: 'Vue grille avec vignettes images & vidéos. Liste ou grille, mode « Médias ».'
  },
  en: {
    h: 'A real media\ngallery.',
    s: 'Grid view with photo & video thumbnails. List or grid, "Media only" mode.'
  }
}, {
  id: 'home',
  Screen: ScreenHome,
  palette: 'cream',
  fr: {
    h: 'Votre centre\nde contrôle.',
    s: 'Transferts, favoris, sync photo, débit. En un coup d\'œil.'
  },
  en: {
    h: 'Your control\ncenter.',
    s: 'Transfers, pins, photo sync, throughput. At a glance.'
  }
}, {
  id: 'wizard',
  Screen: ScreenWizard,
  palette: 'forest',
  fr: {
    h: 'Assistant\nguidé.',
    s: 'OAuth en deux tapotements. Import rclone.conf en un geste.'
  },
  en: {
    h: 'Guided\nsetup.',
    s: 'OAuth in two taps. rclone.conf import in one gesture.'
  }
}, {
  id: 'photos',
  Screen: ScreenPhotoSync,
  palette: 'rose',
  fr: {
    h: 'Backup photo,\nintelligent.',
    s: 'Throttle adaptatif, reprise réseau, exécution en arrière-plan.'
  },
  en: {
    h: 'Smart photo\nbackup.',
    s: 'Adaptive throttle, network resume, background tasks.'
  }
}, {
  id: 'privacy',
  Screen: ScreenSecurity,
  palette: 'midnight',
  fr: {
    h: 'Zéro tracker.\nZéro serveur.',
    s: 'Aucune analytics. Open source. ATS strict, TLS 1.3 partout.'
  },
  en: {
    h: 'Zero trackers.\nZero servers.',
    s: 'No analytics. Open source. Strict ATS, TLS 1.3 everywhere.'
  }
}];

/* ════════════════════════════════════════════════════════════════════
   Landing page
   ════════════════════════════════════════════════════════════════════ */
const ML = s => s.split('\n').map((l, i, a) => /*#__PURE__*/React.createElement(React.Fragment, {
  key: i
}, l, i < a.length - 1 && /*#__PURE__*/React.createElement("br", null)));
const AppleLogo = () => /*#__PURE__*/React.createElement("svg", {
  viewBox: "0 0 24 24",
  fill: "currentColor"
}, /*#__PURE__*/React.createElement("path", {
  d: "M16.37 1.43c0 1.14-.42 2.2-1.12 2.98-.85.95-2.22 1.68-3.36 1.59-.14-1.12.44-2.29 1.11-3.02C13.76 2.13 15.16 1.42 16.37 1.43Zm4.1 15.83c-.55 1.27-.81 1.84-1.52 2.96-.99 1.56-2.38 3.49-4.11 3.51-1.53.02-1.93-1-4.01-.99-2.08.01-2.52 1.01-4.05.99-1.73-.02-3.05-1.77-4.04-3.33-2.76-4.34-3.05-9.43-1.35-12.13 1.21-1.92 3.12-3.04 4.92-3.04 1.83 0 2.98 1 4.49 1 1.47 0 2.36-1 4.48-1 1.6 0 3.3.87 4.51 2.38-3.96 2.17-3.32 7.82.68 9.65Z"
}));
const AppStoreBadge = () => {
  const t = useT();
  return /*#__PURE__*/React.createElement("a", {
    className: "appstore",
    href: APP_STORE_URL,
    target: "_blank",
    rel: "noopener"
  }, /*#__PURE__*/React.createElement(AppleLogo, null), /*#__PURE__*/React.createElement("span", null, /*#__PURE__*/React.createElement("span", {
    className: "l1"
  }, t('Télécharger sur l\'', 'Download on the')), /*#__PURE__*/React.createElement("span", {
    className: "l2"
  }, "App Store")));
};
const Header = ({
  lang,
  setLang
}) => {
  const t = useT();
  return /*#__PURE__*/React.createElement("header", {
    className: "nav"
  }, /*#__PURE__*/React.createElement("div", {
    className: "wrap nav-in"
  }, /*#__PURE__*/React.createElement("a", {
    className: "brand",
    href: "#top"
  }, /*#__PURE__*/React.createElement("img", {
    src: "icon.png",
    alt: "Rclone GUI"
  }), "Rclone GUI"), /*#__PURE__*/React.createElement("div", {
    className: "nav-sp"
  }), /*#__PURE__*/React.createElement("a", {
    className: "ghost navlink",
    href: "#versions"
  }, t('Nouveautés', 'What\'s new')), /*#__PURE__*/React.createElement("a", {
    className: "ghost navlink",
    href: "#roadmap"
  }, "Roadmap"), /*#__PURE__*/React.createElement("a", {
    className: "ghost navlink",
    href: "#faq"
  }, "FAQ"), /*#__PURE__*/React.createElement("a", {
    className: "ghost",
    href: GITHUB_URL,
    target: "_blank",
    rel: "noopener",
    style: {
      marginRight: 6
    }
  }, "GitHub"), /*#__PURE__*/React.createElement("div", {
    className: "lang"
  }, /*#__PURE__*/React.createElement("button", {
    className: lang === 'en' ? 'on' : '',
    onClick: () => setLang('en')
  }, "EN"), /*#__PURE__*/React.createElement("button", {
    className: lang === 'fr' ? 'on' : '',
    onClick: () => setLang('fr')
  }, "FR"))));
};
const Hero = () => {
  const t = useT();
  return /*#__PURE__*/React.createElement("section", {
    className: "hero",
    id: "top"
  }, /*#__PURE__*/React.createElement("div", {
    className: "wrap"
  }, /*#__PURE__*/React.createElement("img", {
    className: "icon",
    src: "icon.png",
    alt: "Rclone GUI"
  }), /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("span", {
    className: "pill"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "bolt.fill",
    size: 14
  }), t('v1.6 · ESSAI GRATUIT', 'v1.6 · FREE TRIAL'))), /*#__PURE__*/React.createElement("h1", {
    className: "title"
  }, ML(t('Tous vos clouds.\nChiffrés.', 'Every cloud.\nEncrypted.'))), /*#__PURE__*/React.createElement("p", {
    className: "sub"
  }, t('Parcourez 80+ services cloud — y compris vos remotes rclone chiffrés — directement dans Fichiers. iPhone, iPad & Mac.', 'Browse 80+ cloud services — including your encrypted rclone crypt remotes — right inside Files. iPhone, iPad & Mac.')), /*#__PURE__*/React.createElement("div", {
    className: "cta-row"
  }, /*#__PURE__*/React.createElement("a", {
    className: "btn btn-violet",
    href: "#free"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "bolt.fill",
    size: 18
  }), t('Essayer gratuitement', 'Try it free')), /*#__PURE__*/React.createElement(AppStoreBadge, null)), /*#__PURE__*/React.createElement("p", {
    className: "priceline"
  }, /*#__PURE__*/React.createElement("span", {
    className: "freetag"
  }, t('Essai gratuit', 'Free trial')), t(', puis ', ' · then '), /*#__PURE__*/React.createElement("b", null, t('29,99 € à vie', '€29.99 lifetime')), t(' ou dès ', ' or from '), /*#__PURE__*/React.createElement("b", null, t('2,99 €/mois', '€2.99/mo'))), /*#__PURE__*/React.createElement("p", {
    className: "alt"
  }, t('Ou ', 'Or '), /*#__PURE__*/React.createElement("a", {
    href: GITHUB_URL,
    target: "_blank",
    rel: "noopener"
  }, t('compilez-la gratuitement', 'build it for free')), t(' — c\'est open source', ' — it\'s open source')), /*#__PURE__*/React.createElement("div", {
    className: "trust"
  }, /*#__PURE__*/React.createElement("span", null, /*#__PURE__*/React.createElement(Icon, {
    name: "lock.fill",
    size: 15,
    style: {
      color: ACCENT
    }
  }), t('Chiffrement de bout en bout', 'End-to-end crypt')), /*#__PURE__*/React.createElement("span", null, /*#__PURE__*/React.createElement(Icon, {
    name: "shield.fill",
    size: 15,
    style: {
      color: ACCENT
    }
  }), t('Zéro tracker', 'Zero trackers')), /*#__PURE__*/React.createElement("span", null, /*#__PURE__*/React.createElement(Icon, {
    name: "check.circle",
    size: 15,
    style: {
      color: ACCENT
    }
  }), t('Open source', 'Open source')))));
};
const PhoneFrame = ({
  Screen,
  w = 270
}) => {
  const scale = w / SCREEN_W;
  const h = SCREEN_H * scale;
  return /*#__PURE__*/React.createElement("div", {
    className: "phone",
    style: {
      width: w + 14,
      height: h + 14
    }
  }, /*#__PURE__*/React.createElement("div", {
    className: "phone-island"
  }), /*#__PURE__*/React.createElement("div", {
    className: "phone-screen",
    style: {
      width: w,
      height: h
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: SCREEN_W,
      height: SCREEN_H,
      transform: `scale(${scale})`,
      transformOrigin: 'top left'
    }
  }, /*#__PURE__*/React.createElement(Screen, null))));
};
const Gallery = ({
  lang
}) => {
  const t = useT();
  return /*#__PURE__*/React.createElement("section", {
    id: "screens"
  }, /*#__PURE__*/React.createElement("div", {
    className: "wrap"
  }, /*#__PURE__*/React.createElement("div", {
    className: "eyebrow"
  }, t('Aperçu', 'Take a look')), /*#__PURE__*/React.createElement("h2", {
    className: "sec"
  }, t('Comme dans Fichiers. En mieux.', 'Just like Files. Only better.')), /*#__PURE__*/React.createElement("p", {
    className: "sec-sub"
  }, t('Faites défiler les écrans de l\'app — chiffrement, 80+ services, streaming, sauvegarde photo.', 'Swipe through the app — encryption, 80+ services, streaming, photo backup.'))), /*#__PURE__*/React.createElement("div", {
    className: "gallery"
  }, SHOTS.map(s => {
    const p = PALETTES[s.palette];
    const copy = s[lang] || s.en;
    const ink = p.dark ? '#fff' : '#0B0820';
    return /*#__PURE__*/React.createElement("div", {
      key: s.id,
      className: "panel",
      style: {
        background: `linear-gradient(180deg, ${p.from} 0%, ${p.to} 100%)`,
        color: ink
      }
    }, s.isNew && /*#__PURE__*/React.createElement("span", {
      className: "newtag"
    }, t('NOUVEAU · v1.5', 'NEW · v1.5')), /*#__PURE__*/React.createElement("div", {
      className: "kick",
      style: {
        color: p.accent
      }
    }, "RCLONE GUI · iOS"), /*#__PURE__*/React.createElement("h3", null, ML(copy.h)), /*#__PURE__*/React.createElement("p", {
      className: "psub"
    }, copy.s), /*#__PURE__*/React.createElement("div", {
      className: "stage"
    }, /*#__PURE__*/React.createElement(PhoneFrame, {
      Screen: s.Screen
    })));
  })));
};
const Features = () => {
  const t = useT();
  const feats = [{
    i: 'lock.fill',
    c: ACCENT,
    t: t('Crypt rclone natif', 'Native rclone crypt'),
    d: t('AES-256 + NaCl secretbox. Vos clés ne quittent jamais l\'appareil.', 'AES-256 + NaCl secretbox. Your keys never leave the device.')
  }, {
    i: 'cloud.fill',
    c: '#1A73E8',
    t: t('80+ services', '80+ services'),
    d: 'S3, R2, Drive, Dropbox, B2, SFTP, WebDAV, Storj, Wasabi…'
  }, {
    i: 'play.fill',
    c: '#C44569',
    t: t('Streaming direct', 'Direct streaming'),
    d: t('Photos, vidéos et PDF ouverts sans tout télécharger.', 'Photos, video and PDF opened without a full download.')
  }, {
    i: 'photo.stack',
    c: '#FF2D55',
    t: t('Backup photo intelligent', 'Smart photo backup'),
    d: t('Débit adaptatif, reprise réseau, exécution en arrière-plan.', 'Adaptive throughput, network resume, background tasks.')
  }, {
    i: 'wand',
    c: '#1F8F4A',
    t: t('Assistant guidé', 'Guided setup'),
    d: t('OAuth en deux tapotements. Import rclone.conf en un geste.', 'OAuth in two taps. rclone.conf import in one gesture.')
  }, {
    i: 'shield.fill',
    c: '#5B21B6',
    t: t('Zéro tracker, open source', 'Zero trackers, open source'),
    d: t('Aucune analytics, aucun serveur tiers. Auditable sur GitHub.', 'No analytics, no third-party server. Auditable on GitHub.')
  }];
  return /*#__PURE__*/React.createElement("section", {
    id: "features"
  }, /*#__PURE__*/React.createElement("div", {
    className: "wrap"
  }, /*#__PURE__*/React.createElement("div", {
    className: "eyebrow"
  }, t('Fonctionnalités', 'Features')), /*#__PURE__*/React.createElement("h2", {
    className: "sec"
  }, t('Pensé pour la confidentialité', 'Built for privacy')), /*#__PURE__*/React.createElement("div", {
    className: "grid"
  }, feats.map(f => /*#__PURE__*/React.createElement("div", {
    key: f.t,
    className: "card"
  }, /*#__PURE__*/React.createElement("div", {
    className: "ic",
    style: {
      background: `linear-gradient(135deg, ${f.c}, ${f.c}cc)`
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: f.i,
    size: 24,
    weight: "semibold"
  })), /*#__PURE__*/React.createElement("h4", null, f.t), /*#__PURE__*/React.createElement("p", null, f.d))))));
};
const Pricing = () => {
  const t = useT();
  const plans = [{
    id: 'lifetime',
    featured: true,
    name: t('À vie', 'Lifetime'),
    price: '29,99 €',
    per: t('paiement unique', 'one-time payment'),
    badge: t('Meilleure offre', 'Best value'),
    points: [t('Payé une fois, à vous pour toujours', 'Pay once, yours forever'), t('iPhone, iPad et Mac inclus', 'iPhone, iPad and Mac included'), t('Toutes les fonctionnalités, à vie', 'Every feature, forever')]
  }, {
    id: 'yearly',
    name: t('Annuel', 'Yearly'),
    price: '11,99 €',
    per: t('par an', 'per year'),
    points: [t('Environ 1 €/mois', 'About €1/month'), t('~67 % d\'économie vs mensuel', '~67% off vs monthly'), t('Renouvelable, annulable', 'Renews, cancel anytime')]
  }, {
    id: 'monthly',
    name: t('Mensuel', 'Monthly'),
    price: '2,99 €',
    per: t('par mois', 'per month'),
    points: [t('Sans engagement', 'No commitment'), t('Annulable à tout moment', 'Cancel anytime'), t('Idéal pour démarrer', 'Great to get started')]
  }];
  return /*#__PURE__*/React.createElement("section", {
    id: "pricing"
  }, /*#__PURE__*/React.createElement("div", {
    className: "wrap"
  }, /*#__PURE__*/React.createElement("div", {
    className: "eyebrow"
  }, t('Tarifs', 'Pricing')), /*#__PURE__*/React.createElement("h2", {
    className: "sec"
  }, t('Payez comme vous voulez', 'Pay your way')), /*#__PURE__*/React.createElement("p", {
    className: "sec-sub"
  }, t('Commencez par l\'essai gratuit. Ensuite, un achat unique à vie ou un abonnement — à vous de choisir.', 'Start with the free trial. Then a one-time lifetime purchase or a subscription — your call.')), /*#__PURE__*/React.createElement("div", {
    className: "pricing-grid"
  }, plans.map(p => /*#__PURE__*/React.createElement("div", {
    key: p.id,
    className: p.featured ? 'plan featured' : 'plan'
  }, p.badge && /*#__PURE__*/React.createElement("div", {
    className: "badge"
  }, p.badge), /*#__PURE__*/React.createElement("div", {
    className: "pname"
  }, p.name), /*#__PURE__*/React.createElement("div", {
    className: "pprice"
  }, p.price), /*#__PURE__*/React.createElement("div", {
    className: "pper"
  }, p.per), /*#__PURE__*/React.createElement("ul", null, p.points.map(pt => /*#__PURE__*/React.createElement("li", {
    key: pt
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "check.circle",
    size: 18
  }), pt)))))), /*#__PURE__*/React.createElement("p", {
    className: "pricing-note"
  }, t('Prix App Store, taxes incluses. L\'essai gratuit ne vous engage à rien.', 'App Store prices, taxes included. The free trial commits you to nothing.'), /*#__PURE__*/React.createElement("span", {
    className: "solid"
  }, t('Étudiant·e, emploi précaire, chômage ou budget serré ? ', 'Student, precarious job, unemployed or on a tight budget? '), /*#__PURE__*/React.createElement("a", {
    href: "mailto:vitalys@rougetet.com?subject=Rclone%20GUI%20%E2%80%94%20Demande%20de%20r%C3%A9duction%20(selon%20mes%20moyens)"
  }, t('Demandez une réduction selon vos moyens.', 'Ask for a discount based on your means.'))))));
};
const FreeMonth = () => {
  const t = useT();
  const lang = React.useContext(LangContext);
  const STORE_KEY = 'rclone_trial_code_v1';
  const [state, setState] = React.useState('idle'); // idle|loading|done|soldout|error
  const [email, setEmail] = React.useState('');
  const [newsletter, setNewsletter] = React.useState(false);
  const [emailErr, setEmailErr] = React.useState(false);
  const [code, setCode] = React.useState(null);
  const [url, setUrl] = React.useState(null);
  const [copied, setCopied] = React.useState(false);
  React.useEffect(() => {
    try {
      const saved = JSON.parse(localStorage.getItem(STORE_KEY) || 'null');
      if (saved && saved.code) {
        setCode(saved.code);
        setUrl(saved.url);
        setState('done');
      }
    } catch (e) {}
  }, []);
  const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
  const claim = async () => {
    const mail = email.trim().toLowerCase();
    if (!EMAIL_RE.test(mail)) {
      setEmailErr(true);
      return;
    }
    setEmailErr(false);
    setState('loading');
    try {
      const res = await fetch(CLAIM_API, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          email: mail,
          newsletter,
          lang
        })
      });
      const data = await res.json().catch(() => ({}));
      if (res.ok && data.sent) {
        setState('sent');
      } else if (res.ok && data.code) {
        setCode(data.code);
        setUrl(data.url);
        try {
          localStorage.setItem(STORE_KEY, JSON.stringify({
            code: data.code,
            url: data.url
          }));
        } catch (e) {}
        setState('done');
      } else if (res.status === 400 || data.error === 'invalid_email') {
        setEmailErr(true);
        setState('idle');
      } else if (res.status === 429 || data.error === 'ip_blocked') {
        setState('ipblocked');
      } else if (res.status === 410 || data.error === 'sold_out') {
        setState('soldout');
      } else {
        setState('error');
      }
    } catch (e) {
      setState('error');
    }
  };
  const redeemUrl = url || (code ? `https://apps.apple.com/redeem?ctx=offercodes&id=${APP_ID}&code=${code}` : APP_STORE_URL);
  const copy = async () => {
    try {
      await navigator.clipboard.writeText(code);
      setCopied(true);
      setTimeout(() => setCopied(false), 1800);
    } catch (e) {}
  };
  return /*#__PURE__*/React.createElement("section", {
    id: "free"
  }, /*#__PURE__*/React.createElement("div", {
    className: "wrap"
  }, /*#__PURE__*/React.createElement("div", {
    className: "free"
  }, /*#__PURE__*/React.createElement("div", {
    className: "gift"
  }, "🎁"), /*#__PURE__*/React.createElement("h2", null, t('Un mois offert', 'One month free')), /*#__PURE__*/React.createElement("p", {
    className: "lede"
  }, t('Un code App Store personnel, valable une fois, pour démarrer votre essai sans frais. Un par personne.', 'A personal, single-use App Store code to start your trial at no cost. One per person.')), /*#__PURE__*/React.createElement("div", {
    className: "claimbox"
  }, state === 'idle' && /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("input", {
    className: "field",
    type: "email",
    inputMode: "email",
    autoComplete: "email",
    placeholder: t('Votre adresse e-mail', 'Your email address'),
    value: email,
    onChange: e => {
      setEmail(e.target.value);
      if (emailErr) setEmailErr(false);
    },
    onKeyDown: e => {
      if (e.key === 'Enter') claim();
    },
    style: emailErr ? {
      borderColor: '#fff',
      boxShadow: '0 0 0 3px rgba(255,255,255,.55)'
    } : null
  }), emailErr && /*#__PURE__*/React.createElement("p", {
    className: "mini",
    style: {
      marginTop: 8,
      fontWeight: 700
    }
  }, t('Entrez une adresse e-mail valide.', 'Please enter a valid email address.')), /*#__PURE__*/React.createElement("label", {
    className: "optin"
  }, /*#__PURE__*/React.createElement("input", {
    type: "checkbox",
    checked: newsletter,
    onChange: e => setNewsletter(e.target.checked)
  }), /*#__PURE__*/React.createElement("span", null, t('Tenez-moi informé des nouveautés (newsletter, sans spam).', 'Keep me posted about updates (newsletter, no spam).'))), /*#__PURE__*/React.createElement("button", {
    className: "btn btn-light btn-big",
    onClick: claim
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "bolt.fill",
    size: 18
  }), t('Obtenir mon code', 'Get my code')), /*#__PURE__*/React.createElement("p", {
    className: "mini"
  }, t('Votre e-mail garantit un code par personne. Jamais partagé avec des tiers.', 'Your email ensures one code per person. Never shared with third parties.'))), state === 'loading' && /*#__PURE__*/React.createElement("button", {
    className: "btn btn-light btn-big",
    disabled: true
  }, /*#__PURE__*/React.createElement("span", {
    className: "spinner"
  }), t('Génération…', 'Generating…')), state === 'done' && /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 13,
      fontWeight: 700,
      letterSpacing: .5,
      opacity: .85,
      marginBottom: 10
    }
  }, t('VOTRE CODE', 'YOUR CODE')), /*#__PURE__*/React.createElement("div", {
    className: "code"
  }, code), /*#__PURE__*/React.createElement("div", {
    className: "row2"
  }, /*#__PURE__*/React.createElement("a", {
    className: "btn btn-light",
    href: redeemUrl,
    target: "_blank",
    rel: "noopener"
  }, /*#__PURE__*/React.createElement(AppleLogo, null), t('Utiliser sur l\'App Store', 'Redeem on App Store')), /*#__PURE__*/React.createElement("button", {
    className: "btn",
    style: {
      background: 'rgba(255,255,255,.18)',
      color: '#fff'
    },
    onClick: copy
  }, copied ? t('Copié ✓', 'Copied ✓') : t('Copier', 'Copy'))), /*#__PURE__*/React.createElement("p", {
    className: "mini"
  }, t('Ouvrez le lien sur votre iPhone/iPad/Mac connecté à l\'App Store, ou saisissez le code dans App Store → votre photo → « Utiliser une carte cadeau ou un code ».', 'Open the link on your iPhone/iPad/Mac signed in to the App Store, or enter the code in App Store → your photo → “Redeem Gift Card or Code”.'))), state === 'sent' && /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 40,
      lineHeight: 1
    }
  }, "📬"), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 20,
      fontWeight: 800,
      margin: '8px 0 4px'
    }
  }, t('Vérifiez votre boîte mail', 'Check your inbox')), /*#__PURE__*/React.createElement("p", {
    className: "mini",
    style: {
      opacity: .95
    }
  }, t('Votre code vient d\'être envoyé à votre adresse e-mail (pensez à regarder les spams). Ouvrez-le sur votre appareil Apple pour l\'utiliser.', 'Your code has just been sent to your email (check spam too). Open it on your Apple device to redeem.'))), state === 'ipblocked' && /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 18,
      fontWeight: 700,
      marginBottom: 6
    }
  }, t('Déjà réclamé', 'Already claimed')), /*#__PURE__*/React.createElement("p", {
    className: "mini",
    style: {
      opacity: .95
    }
  }, t('Un code a déjà été demandé depuis cet appareil ou ce réseau. Un seul par personne.', 'A code has already been requested from this device or network. One per person.')), /*#__PURE__*/React.createElement("a", {
    className: "btn btn-light",
    style: {
      marginTop: 14
    },
    href: APP_STORE_URL,
    target: "_blank",
    rel: "noopener"
  }, /*#__PURE__*/React.createElement(AppleLogo, null), "App Store")), state === 'soldout' && /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 18,
      fontWeight: 700,
      marginBottom: 6
    }
  }, t('Plus de codes', 'All codes claimed')), /*#__PURE__*/React.createElement("p", {
    className: "mini",
    style: {
      opacity: .95
    }
  }, t('Tous les codes ont été distribués pour le moment. Vous pouvez quand même télécharger l\'app.', 'All free codes are gone for now. You can still download the app.')), /*#__PURE__*/React.createElement("a", {
    className: "btn btn-light",
    style: {
      marginTop: 14
    },
    href: APP_STORE_URL,
    target: "_blank",
    rel: "noopener"
  }, /*#__PURE__*/React.createElement(AppleLogo, null), "App Store")), state === 'error' && /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("button", {
    className: "btn btn-light btn-big",
    onClick: claim
  }, t('Réessayer', 'Try again')), /*#__PURE__*/React.createElement("p", {
    className: "mini"
  }, t('Une erreur est survenue — vérifiez votre connexion et réessayez.', 'Something went wrong — check your connection and try again.')))), /*#__PURE__*/React.createElement("div", {
    className: "steps"
  }, [{
    n: 1,
    h: t('Récupérez le code', 'Grab your code'),
    p: t('Un clic, un code unique rien que pour vous.', 'One click, one unique code just for you.')
  }, {
    n: 2,
    h: t('Ouvrez l\'App Store', 'Open the App Store'),
    p: t('Le lien ouvre directement l\'écran d\'échange.', 'The link opens the redeem screen directly.')
  }, {
    n: 3,
    h: t('Profitez d\'un mois', 'Enjoy a month'),
    p: t('Votre essai démarre, sans engagement.', 'Your trial starts, no commitment.')
  }].map(s => /*#__PURE__*/React.createElement("div", {
    key: s.n,
    className: "step"
  }, /*#__PURE__*/React.createElement("div", {
    className: "n"
  }, s.n), /*#__PURE__*/React.createElement("h5", null, s.h), /*#__PURE__*/React.createElement("p", null, s.p)))))));
};
const VERSIONS = [{
  v: '1.6',
  current: true,
  date: {
    fr: 'Juin 2026',
    en: 'June 2026'
  },
  items: [{
    fr: 'Connexion par fichier : quand un backend exige un fichier pour s\'authentifier (clé privée SSH, known_hosts, JSON de compte de service Google, certificat TLS…), importez-le directement depuis Fichiers — fini les chemins impossibles à saisir.',
    en: 'Connect with a file: when a backend needs a file to sign in (SSH private key, known_hosts, Google service-account JSON, TLS certificate…), import it straight from Files — no more impossible-to-type paths.'
  }, {
    fr: 'Les identifiants importés sont copiés en sécurité sur l\'appareil et ne sont jamais transmis ailleurs.',
    en: 'Imported credentials are copied securely on-device and never sent anywhere else.'
  }, {
    fr: 'Améliorations de stabilité et de performance.',
    en: 'Stability and performance improvements.'
  }]
}, {
  v: '1.5',
  date: {
    fr: 'Juin 2026',
    en: 'June 2026'
  },
  items: [{
    fr: 'Lecteur vidéo intégré multi-format (MKV, AVI, WebM, TS…) : sous-titres intégrés et fichiers externes, pistes audio, reprise là où vous étiez.',
    en: 'Built-in multi-format video player (MKV, AVI, WebM, TS…): embedded and sidecar subtitles, audio tracks, resume where you left off.'
  }, {
    fr: 'Au choix : lecture dans l\'app ou dans une app externe (Infuse, VLC).',
    en: 'Your choice: play in-app or in an external app (Infuse, VLC).'
  }, {
    fr: 'Galerie en grille avec vignettes pour photos et vidéos : bascule liste/grille, mode « Médias uniquement », génération des vignettes en Wi-Fi par défaut.',
    en: 'Grid gallery with thumbnails for photos and videos: list/grid toggle, "Media only" mode, Wi-Fi-only thumbnail generation by default.'
  }, {
    fr: 'Nouvelle option pour exclure les données de l\'app des sauvegardes iCloud.',
    en: 'New option to exclude the app\'s data from iCloud backups.'
  }, {
    fr: 'Stabilité et performances.',
    en: 'Stability and performance improvements.'
  }]
}, {
  v: '1.4',
  date: {
    fr: 'Juin 2026',
    en: 'June 2026'
  },
  items: [{
    fr: 'Nouveaux clouds : Drime, Internxt et Filen (Internxt et Filen chiffrés de bout en bout).',
    en: 'New clouds: Drime, Internxt and Filen (Internxt and Filen are end-to-end encrypted).'
  }, {
    fr: 'Panneau « où trouver vos identifiants » pour Pixeldrain, 1Fichier, ImageKit, Internet Archive, Gofile, Storj, NetStorage…',
    en: '"Where to get your credentials" panel for Pixeldrain, 1Fichier, ImageKit, Internet Archive, Gofile, Storj, NetStorage…'
  }, {
    fr: 'Sélecteur de stockage pour les remotes composites (alias, union, combine) — fini la saisie manuelle de « remote:chemin ».',
    en: 'Storage picker for composite remotes (alias, union, combine) — no more typing "remote:path" by hand.'
  }, {
    fr: 'Correction de la connexion aux remotes protégés par mot de passe (SFTP, FTP, WebDAV, SMB…).',
    en: 'Fixed connecting to password-protected remotes (SFTP, FTP, WebDAV, SMB…).'
  }, {
    fr: 'Remotes verrouillés masqués des Récents et Favoris.',
    en: 'Locked remotes hidden from Recents and Favorites.'
  }]
}, {
  v: '1.3',
  date: {
    fr: 'Juin 2026',
    en: 'June 2026'
  },
  items: [{
    fr: 'Correctif important : l\'import d\'une configuration rclone chiffrée par mot de passe ne plante plus.',
    en: 'Important fix: importing a password-encrypted rclone configuration no longer crashes the app.'
  }, {
    fr: 'Bouton « J\'ai un code » pour utiliser des codes promo.',
    en: '"I have a code" button to redeem promo codes.'
  }, {
    fr: 'Page « Contacter le développeur » dans Réglages → Support.',
    en: '"Contact the Developer" page in Settings → Support.'
  }, {
    fr: 'Traduction anglaise complète de l\'app + code source désormais public sur GitHub.',
    en: 'Completed English translation across the whole app + source code now public on GitHub.'
  }]
}, {
  v: '1.2',
  date: {
    fr: 'Juin 2026',
    en: 'June 2026'
  },
  items: [{
    fr: 'App macOS native (Mac Apple Silicon) : barre latérale et intégration Finder.',
    en: 'Native macOS app (Apple Silicon Macs): sidebar layout and Finder integration.'
  }, {
    fr: 'Assistant guidé pour les remotes chiffrés (crypt) : choix du stockage, navigation jusqu\'au dossier, mot de passe — sans saisie de chemin.',
    en: 'Guided wizard for encrypted (crypt) remotes: pick storage, browse to the folder, set a password — no manual path typing.'
  }, {
    fr: 'Assistant d\'ajout amélioré : bouton Retour et sélecteur de fichier natif pour importer rclone.conf.',
    en: 'Improved add-remote wizard: Back button and native file picker to import rclone.conf.'
  }]
}, {
  v: '1.1',
  date: {
    fr: 'Mai 2026',
    en: 'May 2026'
  },
  items: [{
    fr: 'Localisation anglaise complète : l\'interface suit la langue de l\'appareil.',
    en: 'Full English localization: the interface follows your device language.'
  }, {
    fr: 'Première ouverture plus fluide, stabilité et finitions.',
    en: 'Smoother first-launch, stability and polish.'
  }]
}, {
  v: '1.0',
  date: {
    fr: 'Mai 2026',
    en: 'May 2026'
  },
  items: [{
    fr: 'Première version publique : client rclone natif, 70+ backends, intégration Fichiers (File Provider), chiffrement crypt de bout en bout, sync photo, Face ID, zéro tracking.',
    en: 'First public release: native rclone client, 70+ backends, Files integration (File Provider), end-to-end crypt encryption, photo sync, Face ID, zero tracking.'
  }]
}];
const Versions = () => {
  const t = useT();
  const lang = React.useContext(LangContext);
  return /*#__PURE__*/React.createElement("section", {
    id: "versions"
  }, /*#__PURE__*/React.createElement("div", {
    className: "wrap"
  }, /*#__PURE__*/React.createElement("div", {
    className: "eyebrow"
  }, t('Nouveautés', 'What\'s new')), /*#__PURE__*/React.createElement("h2", {
    className: "sec"
  }, t('Chaque version, en mieux', 'Every release, better')), /*#__PURE__*/React.createElement("p", {
    className: "sec-sub"
  }, t('L\'historique complet des mises à jour et ce qu\'elles apportent.', 'The full update history and what each one adds.')), /*#__PURE__*/React.createElement("div", {
    className: "versions"
  }, VERSIONS.map(rel => /*#__PURE__*/React.createElement("div", {
    key: rel.v,
    className: rel.current ? 'ver current' : 'ver'
  }, /*#__PURE__*/React.createElement("div", {
    className: "ver-head"
  }, /*#__PURE__*/React.createElement("span", {
    className: "ver-num"
  }, t('Version ', 'Version '), rel.v), /*#__PURE__*/React.createElement("span", {
    className: "ver-date"
  }, rel.date[lang] || rel.date.en), rel.current && /*#__PURE__*/React.createElement("span", {
    className: "ver-tag"
  }, t('ACTUELLE', 'CURRENT'))), /*#__PURE__*/React.createElement("ul", {
    className: "ver-list"
  }, rel.items.map((it, i) => /*#__PURE__*/React.createElement("li", {
    key: i
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "check.circle",
    size: 18
  }), it[lang] || it.en))))))));
};
const ROADMAP = [{
  key: 'short',
  label: {
    fr: 'Court terme',
    en: 'Short term'
  },
  tag: {
    fr: 'EN PRÉPARATION',
    en: 'IN PROGRESS'
  },
  items: [{
    n: {
      fr: 'Transferts Pro',
      en: 'Pro Transfers'
    },
    d: {
      fr: 'File d\'attente, priorités, reprise robuste, limites Wi-Fi/cellulaire, logs exportables.',
      en: 'Queue, priorities, robust resume, Wi-Fi/cellular limits, exportable logs.'
    }
  }, {
    n: {
      fr: 'Flows',
      en: 'Flows'
    },
    d: {
      fr: 'Automatisations 100 % locales (Raccourcis + App Intents) et Live Activity « santé du backup ».',
      en: '100% local automations (Shortcuts + App Intents) and a "backup health" Live Activity.'
    }
  }, {
    n: {
      fr: 'Ghost Vault',
      en: 'Ghost Vault'
    },
    d: {
      fr: 'Sauvegarde chiffrée de toute ta config dans ton propre remote, scellée par Face ID. Sans compte.',
      en: 'Encrypted backup of your whole config into your own remote, sealed with Face ID. No account.'
    }
  }, {
    n: {
      fr: 'Handoff P2P',
      en: 'P2P Handoff'
    },
    d: {
      fr: 'Transférer une config chiffrée entre tes appareils via QR / AirDrop, sans serveur.',
      en: 'Move an encrypted config between your devices via QR / AirDrop, with no server.'
    }
  }, {
    n: {
      fr: 'Glass Engine',
      en: 'Glass Engine'
    },
    d: {
      fr: 'Moniteur « 0 appel maison » + build reproductible : prouver le privacy, pas le promettre.',
      en: 'A "zero phone-home" monitor + reproducible build: prove privacy, don\'t just promise it.'
    }
  }]
}, {
  key: 'mid',
  label: {
    fr: 'Moyen terme',
    en: 'Mid term'
  },
  tag: {
    fr: 'PRÉVU',
    en: 'PLANNED'
  },
  items: [{
    n: {
      fr: 'Remote Lens',
      en: 'Remote Lens'
    },
    d: {
      fr: 'Aperçus (vignettes, EXIF, 1re page PDF) par range requests, sans tout télécharger ni déchiffrer.',
      en: 'Previews (thumbnails, EXIF, first PDF page) via range requests, without downloading or fully decrypting.'
    }
  }, {
    n: {
      fr: 'Recherche sémantique on-device',
      en: 'On-device semantic search'
    },
    d: {
      fr: 'Médiathèque locale chiffrée + recherche en langage naturel (Apple Intelligence), jamais côté serveur.',
      en: 'Local encrypted media library + natural-language search (Apple Intelligence), never server-side.'
    }
  }, {
    n: {
      fr: 'Sealed Share',
      en: 'Sealed Share'
    },
    d: {
      fr: 'Partage hors-bande : lien backend natif + capsule-clé via AirDrop/QR, déchiffrement on-device.',
      en: 'Out-of-band sharing: native backend link + key capsule via AirDrop/QR, decrypted on-device.'
    }
  }, {
    n: {
      fr: 'Règles de sync',
      en: 'Sync rules'
    },
    d: {
      fr: 'Règles locales par type/dossier + « toujours disponible hors-ligne » depuis Fichiers.',
      en: 'Local rules by type/folder + "always available offline" from Files.'
    }
  }, {
    n: {
      fr: 'Mode Voyage',
      en: 'Travel Mode'
    },
    d: {
      fr: 'Coffre éphémère (déchiffrement en RAM), auto-démontage et Face ID par remote.',
      en: 'Ephemeral vault (in-RAM decryption), auto-unmount and per-remote Face ID.'
    }
  }]
}, {
  key: 'long',
  label: {
    fr: 'Long terme',
    en: 'Long term'
  },
  tag: {
    fr: 'VISION',
    en: 'VISION'
  },
  items: [{
    n: {
      fr: 'ChronoDrive',
      en: 'ChronoDrive'
    },
    d: {
      fr: 'N\'importe quel backend comme destination de sauvegarde versionnée façon Time Machine (macOS), chiffrée.',
      en: 'Any backend as a versioned, encrypted Time Machine-style backup destination (macOS).'
    }
  }, {
    n: {
      fr: 'Ghost Sync',
      en: 'Ghost Sync'
    },
    d: {
      fr: 'Mesh P2P : réconciliation de deltas chiffrés entre tes appareils en réseau local, offline-first.',
      en: 'P2P mesh: encrypted delta reconciliation between your devices over the local network, offline-first.'
    }
  }, {
    n: {
      fr: 'Quantum Vault',
      en: 'Quantum Vault'
    },
    d: {
      fr: 'Chiffrement post-quantique hybride (Kyber + AES) pour des archives « 2035-proof ».',
      en: 'Hybrid post-quantum encryption (Kyber + AES) for "2035-proof" archives.'
    }
  }, {
    n: {
      fr: 'CipherSpace',
      en: 'CipherSpace'
    },
    d: {
      fr: 'Explorer ses archives chiffrées dans l\'espace, sur visionOS.',
      en: 'Explore your encrypted archives in space, on visionOS.'
    }
  }, {
    n: {
      fr: 'Héritage numérique',
      en: 'Digital legacy'
    },
    d: {
      fr: 'Récupération sociale (partage de secret de Shamir) entre contacts de confiance + preuve de vie.',
      en: 'Social recovery (Shamir secret sharing) among trusted contacts + proof of life.'
    }
  }]
}];
const Roadmap = ({
  lang
}) => {
  const t = useT();
  return /*#__PURE__*/React.createElement("section", {
    id: "roadmap"
  }, /*#__PURE__*/React.createElement("div", {
    className: "wrap"
  }, /*#__PURE__*/React.createElement("div", {
    className: "eyebrow"
  }, "Roadmap"), /*#__PURE__*/React.createElement("h2", {
    className: "sec"
  }, t('Et après ?', 'What\'s next?')), /*#__PURE__*/React.createElement("p", {
    className: "sec-sub"
  }, t('Notre cap : ton cloud, sans intermédiaire. Tout reste privacy-first, open source et sans serveur backend.', 'Our heading: your cloud, no middleman. Everything stays privacy-first, open source and backend-free.')), /*#__PURE__*/React.createElement("div", {
    className: "roadmap"
  }, ROADMAP.map(col => /*#__PURE__*/React.createElement("div", {
    key: col.key,
    className: 'rm-col rm-' + col.key
  }, /*#__PURE__*/React.createElement("div", {
    className: "rm-head"
  }, /*#__PURE__*/React.createElement("span", {
    className: "rm-label"
  }, col.label[lang] || col.label.en), /*#__PURE__*/React.createElement("span", {
    className: "rm-tag"
  }, col.tag[lang] || col.tag.en)), /*#__PURE__*/React.createElement("div", {
    className: "rm-items"
  }, col.items.map(it => /*#__PURE__*/React.createElement("div", {
    key: it.n.en,
    className: "rm-item"
  }, /*#__PURE__*/React.createElement("h5", null, it.n[lang] || it.n.en), /*#__PURE__*/React.createElement("p", null, it.d[lang] || it.d.en))))))), /*#__PURE__*/React.createElement("div", {
    className: "rm-bet"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "bolt.fill",
    size: 16
  }), /*#__PURE__*/React.createElement("span", null, /*#__PURE__*/React.createElement("b", null, t('Pari produit', 'Product bet'), " : "), t('« Capability, pas compte » — le partage et le multi-appareils deviennent des objets cryptographiques que tu possèdes et révoques, jamais une ligne dans une base (puisqu\'il n\'y en a pas).', '"Capability, not account" — sharing and multi-device become cryptographic objects you own and revoke, never a row in a database (because there isn\'t one).'))), /*#__PURE__*/React.createElement("p", {
    className: "rm-note"
  }, t('Roadmap indicative, sans engagement de date — priorisée avec vos retours. Open source : suivez ou contribuez sur GitHub.', 'Indicative roadmap, no committed dates — prioritized with your feedback. Open source: follow or contribute on GitHub.'))));
};
const FAQ = () => {
  const t = useT();
  const items = [{
    q: t('Rclone GUI est-il gratuit ?', 'Is Rclone GUI free?'),
    a: t('Il y a un essai gratuit (1 mois via un code personnel sur ce site). Ensuite, un achat unique à vie de 29,99 € (iPhone + iPad + Mac) ou un abonnement dès 2,99 €/mois (11,99 €/an). L\'app est aussi open source : vous pouvez la compiler vous-même gratuitement.', 'There is a free trial (1 month via a personal code on this site). After that, a one-time lifetime purchase of €29.99 (iPhone + iPad + Mac) or a subscription from €2.99/month (€11.99/year). It is also open source, so you can build it yourself for free.')
  }, {
    q: t('Quels services cloud sont pris en charge ?', 'Which cloud services are supported?'),
    a: t('Plus de 80 backends via le moteur rclone : Amazon S3, Cloudflare R2, Google Drive, Dropbox, OneDrive, Backblaze B2, SFTP, WebDAV, Storj, Wasabi, Drime, Internxt, Filen, et bien d\'autres.', '80+ backends through the rclone engine: Amazon S3, Cloudflare R2, Google Drive, Dropbox, OneDrive, Backblaze B2, SFTP, WebDAV, Storj, Wasabi, Drime, Internxt, Filen and many more.')
  }, {
    q: t('Quels formats vidéo puis-je lire ? (v1.5)', 'Which video formats can I play? (v1.5)'),
    a: t('Le lecteur intégré est multi-format : MP4, MOV, M4V, mais aussi MKV, AVI, WebM, TS et plus, grâce à un moteur hybride. Sous-titres (intégrés et fichiers externes) et pistes audio inclus. Vous pouvez aussi ouvrir la vidéo dans une app externe (Infuse, VLC).', 'The built-in player is multi-format: MP4, MOV, M4V, plus MKV, AVI, WebM, TS and more, thanks to a hybrid engine. Subtitles (embedded and sidecar files) and audio tracks included. You can also open videos in an external app (Infuse, VLC).')
  }, {
    q: t('Un backend me demande un fichier (clé SSH, certificat…) : comment faire ? (v1.6)', 'A backend asks for a file (SSH key, certificate…): how do I do that? (v1.6)'),
    a: t('Depuis la v1.6, quand un backend exige un fichier pour se connecter (clé privée SSH, known_hosts, JSON de compte de service Google, certificat TLS, key.pem…), un bouton « Importer un fichier » ouvre l\'app Fichiers : sélectionnez le fichier, c\'est tout. Il est copié en sécurité dans l\'app (jamais transmis ailleurs) ; impossible de saisir un chemin de fichier à la main sur iOS.', 'Since v1.6, when a backend needs a file to connect (SSH private key, known_hosts, Google service-account JSON, TLS certificate, key.pem…), an "Import a file" button opens the Files app: pick the file, done. It is copied securely into the app (never sent anywhere else); typing a filesystem path by hand isn\'t possible on iOS.')
  }, {
    q: t('Mes données sont-elles privées et chiffrées ?', 'Is my data private and encrypted?'),
    a: t('Oui. Le chiffrement rclone « crypt » est natif, avec déchiffrement des noms à la volée ; vos clés ne quittent jamais l\'appareil. Aucun tracker, aucun serveur backend. Vous pouvez aussi exclure les données de l\'app des sauvegardes iCloud (v1.5).', 'Yes. rclone "crypt" encryption is native, with on-the-fly filename decryption; your keys never leave the device. No trackers, no backend server. You can also exclude the app\'s data from iCloud backups (v1.5).')
  }, {
    q: t('Fonctionne-t-il sur Mac et iPad ?', 'Does it work on Mac and iPad?'),
    a: t('Oui : iPhone, iPad et Mac (Apple Silicon, app native depuis la v1.2). L\'achat à vie couvre les trois plateformes.', 'Yes: iPhone, iPad and Mac (Apple Silicon, native app since v1.2). The lifetime purchase covers all three platforms.')
  }, {
    q: t('Comment obtenir une réduction ?', 'How can I get a discount?'),
    a: t('Étudiant·e, emploi précaire, chômage ou budget serré ? Écrivez au développeur pour un code adapté à vos moyens — sans justificatif.', 'Student, precarious job, unemployed or on a tight budget? Email the developer for a code based on what you can afford — no proof required.')
  }, {
    q: t('Est-ce open source ?', 'Is it open source?'),
    a: t('Oui, sous licence MPL-2.0 et auditable sur GitHub. Aucun serveur backend, aucune analytics.', 'Yes, under the MPL-2.0 license and auditable on GitHub. No backend server, no analytics.')
  }];
  return /*#__PURE__*/React.createElement("section", {
    id: "faq"
  }, /*#__PURE__*/React.createElement("div", {
    className: "wrap"
  }, /*#__PURE__*/React.createElement("div", {
    className: "eyebrow"
  }, t('Questions', 'Questions')), /*#__PURE__*/React.createElement("h2", {
    className: "sec"
  }, t('Vos questions', 'Your questions')), /*#__PURE__*/React.createElement("p", {
    className: "sec-sub"
  }, t('Tout ce qu\'il faut savoir avant de vous lancer.', 'Everything you need to know before you start.')), /*#__PURE__*/React.createElement("div", {
    className: "faq"
  }, items.map((it, i) => /*#__PURE__*/React.createElement("details", {
    className: "faq-item",
    key: i,
    open: i === 0
  }, /*#__PURE__*/React.createElement("summary", null, it.q), /*#__PURE__*/React.createElement("p", null, it.a))))));
};
const Footer = () => {
  const t = useT();
  return /*#__PURE__*/React.createElement("footer", null, /*#__PURE__*/React.createElement("div", {
    className: "wrap"
  }, /*#__PURE__*/React.createElement("div", {
    className: "foot"
  }, /*#__PURE__*/React.createElement("a", {
    className: "brand",
    href: "#top"
  }, /*#__PURE__*/React.createElement("img", {
    src: "icon.png",
    alt: "",
    style: {
      width: 26,
      height: 26,
      borderRadius: 7
    }
  }), "Rclone GUI"), /*#__PURE__*/React.createElement("div", {
    className: "nav-sp"
  }), /*#__PURE__*/React.createElement("a", {
    href: "#versions"
  }, t('Nouveautés', 'What\'s new')), /*#__PURE__*/React.createElement("a", {
    href: "#roadmap"
  }, "Roadmap"), /*#__PURE__*/React.createElement("a", {
    href: "#faq"
  }, "FAQ"), /*#__PURE__*/React.createElement("a", {
    href: APP_STORE_URL,
    target: "_blank",
    rel: "noopener"
  }, "App Store"), /*#__PURE__*/React.createElement("a", {
    href: GITHUB_URL,
    target: "_blank",
    rel: "noopener"
  }, "GitHub"), /*#__PURE__*/React.createElement("a", {
    href: "privacy.html"
  }, t('Confidentialité', 'Privacy')), /*#__PURE__*/React.createElement("a", {
    href: "https://rclone.org",
    target: "_blank",
    rel: "noopener"
  }, "rclone.org")), /*#__PURE__*/React.createElement("p", {
    className: "legal"
  }, t('Rclone GUI est un client open-source (MPL-2.0) bâti sur rclone et SwiftUI. « rclone » est une marque de ses détenteurs respectifs ; cette application n\'est pas affiliée. Codes d\'essai limités, un par personne, dans la limite des stocks disponibles.', 'Rclone GUI is an open-source client (MPL-2.0) built on rclone and SwiftUI. “rclone” is a trademark of its respective owners; this app is not affiliated. Trial codes are limited, one per person, while supplies last.'))));
};
const App = () => {
  const [lang, setLang] = React.useState('en');
  return /*#__PURE__*/React.createElement(LangContext.Provider, {
    value: lang
  }, /*#__PURE__*/React.createElement(Header, {
    lang: lang,
    setLang: setLang
  }), /*#__PURE__*/React.createElement(Hero, null), /*#__PURE__*/React.createElement(Gallery, {
    lang: lang
  }), /*#__PURE__*/React.createElement(Features, null), /*#__PURE__*/React.createElement(Versions, null), /*#__PURE__*/React.createElement(Roadmap, {
    lang: lang
  }), /*#__PURE__*/React.createElement(Pricing, null), /*#__PURE__*/React.createElement(FreeMonth, null), /*#__PURE__*/React.createElement(FAQ, null), /*#__PURE__*/React.createElement(Footer, null));
};
ReactDOM.createRoot(document.getElementById('root')).render(/*#__PURE__*/React.createElement(App, null));