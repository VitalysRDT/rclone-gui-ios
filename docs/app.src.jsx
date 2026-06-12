
/* ════════════════════════════════════════════════════════════════════
   Config
   ════════════════════════════════════════════════════════════════════ */
const APP_ID        = '6770088773';
const APP_STORE_URL = 'https://apps.apple.com/app/id' + APP_ID;
const GITHUB_URL    = 'https://github.com/VitalysRDT/rclone-gui-ios';
// Backend qui distribue 1 code par utilisateur (les codes ne sont JAMAIS dans cette page).
const CLAIM_API     = 'https://rclone-gui-trial.vercel.app/api/claim';

/* ════════════════════════════════════════════════════════════════════
   Design system (repris du handoff design — DesignSystem.swift)
   ════════════════════════════════════════════════════════════════════ */
const ACCENT = '#7C3AED';
const ACCENT_DEEP = '#5B21B6';
const ACCENT_SOFT = 'rgba(124, 58, 237, 0.18)';

const LangContext = React.createContext('en');
const useT = () => {
  const lang = React.useContext(LangContext);
  return (fr, en) => (lang === 'fr' ? fr : (en === undefined ? fr : en));
};

const BACKEND_COLORS = {
  s3:'#FF9500', b2:'#E5392F', sftp:'#34C759', ftp:'#008099', webdav:'#5856D6',
  drive:'#1A73E8', dropbox:'#0061FF', onedrive:'#0364B8', box:'#0061D5',
  crypt:ACCENT, local:'#8E8E93', mega:'#D9272E', pcloud:'#16A085',
  storj:'#2683FF', wasabi:'#01B636', generic:'#8E8E93',
};
const BACKEND_GLYPHS = {
  s3:'cloud.fill', b2:'cloud.fill', drive:'cloud.fill', dropbox:'cloud.fill',
  onedrive:'cloud.fill', box:'cloud.fill', mega:'cloud.fill', pcloud:'cloud.fill',
  storj:'cloud.fill', wasabi:'cloud.fill', sftp:'server', ftp:'server',
  webdav:'globe', crypt:'lock.fill', local:'folder.fill',
};

const Icon = ({ name, size = 18, weight = 'regular', style }) => {
  const sw = weight === 'bold' ? 2.4 : weight === 'semibold' ? 2 : 1.7;
  const common = { width:size, height:size, viewBox:'0 0 24 24', fill:'none',
    stroke:'currentColor', strokeWidth:sw, strokeLinecap:'round', strokeLinejoin:'round', style };
  switch (name) {
    case 'lock': return <svg {...common}><rect x="4.5" y="10.5" width="15" height="10.5" rx="2.5"/><path d="M7.5 10.5V7a4.5 4.5 0 1 1 9 0v3.5"/></svg>;
    case 'lock.fill': return <svg {...common} fill="currentColor" stroke="none"><path d="M7.5 7a4.5 4.5 0 1 1 9 0v3.5h-2V7a2.5 2.5 0 0 0-5 0v3.5h-2V7Z"/><rect x="4.5" y="10.5" width="15" height="10.5" rx="2.5"/></svg>;
    case 'cloud': return <svg {...common}><path d="M7 18a4 4 0 0 1-.6-7.95 5.5 5.5 0 0 1 10.7-.7A4 4 0 0 1 17 18H7Z"/></svg>;
    case 'cloud.fill': return <svg {...common} fill="currentColor" stroke="none"><path d="M7 18a4 4 0 0 1-.6-7.95 5.5 5.5 0 0 1 10.7-.7A4 4 0 0 1 17 18H7Z"/></svg>;
    case 'folder': return <svg {...common}><path d="M3.5 7.5A1.5 1.5 0 0 1 5 6h4l2 2h8a1.5 1.5 0 0 1 1.5 1.5v8A1.5 1.5 0 0 1 19 19H5a1.5 1.5 0 0 1-1.5-1.5v-10Z"/></svg>;
    case 'folder.fill': return <svg {...common} fill="currentColor" stroke="currentColor"><path d="M3.5 7.5A1.5 1.5 0 0 1 5 6h4l2 2h8a1.5 1.5 0 0 1 1.5 1.5v8A1.5 1.5 0 0 1 19 19H5a1.5 1.5 0 0 1-1.5-1.5v-10Z"/></svg>;
    case 'externaldrive': return <svg {...common}><rect x="3" y="6" width="18" height="12" rx="2.5"/><circle cx="17" cy="12" r="1" fill="currentColor"/><path d="M7 12h6"/></svg>;
    case 'server': return <svg {...common}><rect x="3.5" y="4" width="17" height="6" rx="1.5"/><rect x="3.5" y="14" width="17" height="6" rx="1.5"/><circle cx="7" cy="7" r=".7" fill="currentColor"/><circle cx="7" cy="17" r=".7" fill="currentColor"/></svg>;
    case 'gear': return <svg {...common}><circle cx="12" cy="12" r="3"/><path d="M19.4 14a1.6 1.6 0 0 0 .3 1.7l.05.05a2 2 0 0 1-2.83 2.83l-.05-.05a1.6 1.6 0 0 0-1.7-.3 1.6 1.6 0 0 0-1 1.46V20a2 2 0 0 1-4 0v-.08a1.6 1.6 0 0 0-1-1.46 1.6 1.6 0 0 0-1.7.3l-.05.05a2 2 0 0 1-2.83-2.83l.05-.05a1.6 1.6 0 0 0 .3-1.7 1.6 1.6 0 0 0-1.46-1H4a2 2 0 0 1 0-4h.08a1.6 1.6 0 0 0 1.46-1 1.6 1.6 0 0 0-.3-1.7l-.05-.05a2 2 0 0 1 2.83-2.83l.05.05a1.6 1.6 0 0 0 1.7.3h.01a1.6 1.6 0 0 0 1-1.46V4a2 2 0 0 1 4 0v.08a1.6 1.6 0 0 0 1 1.46 1.6 1.6 0 0 0 1.7-.3l.05-.05a2 2 0 0 1 2.83 2.83l-.05.05a1.6 1.6 0 0 0-.3 1.7v.01a1.6 1.6 0 0 0 1.46 1H20a2 2 0 0 1 0 4h-.08a1.6 1.6 0 0 0-1.46 1Z"/></svg>;
    case 'arrows': return <svg {...common}><path d="M7 4v14M7 18l-3-3M7 18l3-3"/><path d="M17 20V6M17 6l-3 3M17 6l3 3"/></svg>;
    case 'chevron.right': return <svg {...common}><path d="M9 6l6 6-6 6"/></svg>;
    case 'check': return <svg {...common}><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>;
    case 'check.circle': return <svg {...common} fill="currentColor" stroke="none"><path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20Zm-1.2 14L6.5 11.7l1.4-1.4 2.9 2.9 5.3-5.3 1.4 1.4-6.7 6.7Z"/></svg>;
    case 'plus': return <svg {...common}><path d="M12 5v14M5 12h14"/></svg>;
    case 'plus.circle': return <svg {...common}><circle cx="12" cy="12" r="9"/><path d="M12 8v8M8 12h8"/></svg>;
    case 'magnifying': return <svg {...common}><circle cx="11" cy="11" r="6.5"/><path d="M16 16l4 4"/></svg>;
    case 'clock': return <svg {...common}><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>;
    case 'bolt.fill': return <svg {...common} fill="currentColor" stroke="none"><path d="M14 2 5 13h6l-1 9 9-11h-6l1-9Z"/></svg>;
    case 'photo': return <svg {...common}><rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="9" cy="10.5" r="1.5"/><path d="m3 18 5-5 4 4 3-3 6 6"/></svg>;
    case 'photo.stack': return <svg {...common}><rect x="5" y="7" width="16" height="12" rx="2"/><path d="M3 9v9a2 2 0 0 0 2 2h11"/><circle cx="11" cy="12" r="1.5"/><path d="m7 18 4-4 3 3 2-2 5 5"/></svg>;
    case 'shield.fill': return <svg {...common} fill="currentColor" stroke="none"><path d="M12 3 4 6v6c0 5 3.5 8.5 8 9 4.5-.5 8-4 8-9V6l-8-3Zm-1.2 13L6.5 11.7 7.9 10.3 10.8 13.2 16.1 7.9 17.5 9.3 10.8 16Z"/></svg>;
    case 'faceid': return <svg {...common}><path d="M5 8V6a1 1 0 0 1 1-1h2M19 8V6a1 1 0 0 0-1-1h-2M5 16v2a1 1 0 0 0 1 1h2M19 16v2a1 1 0 0 1-1 1h-2"/><path d="M9 10v2M15 10v2M12 9v4l-1.5 1M9.5 15.5s1 1 2.5 1 2.5-1 2.5-1"/></svg>;
    case 'sparkles': return <svg {...common}><path d="M12 4v3M12 17v3M4 12h3M17 12h3M6.5 6.5l2 2M15.5 15.5l2 2M17.5 6.5l-2 2M8.5 15.5l-2 2"/></svg>;
    case 'doc': return <svg {...common}><path d="M7 3h7l5 5v12a1.5 1.5 0 0 1-1.5 1.5h-10.5A1.5 1.5 0 0 1 5.5 20V4.5A1.5 1.5 0 0 1 7 3Z"/><path d="M14 3v5h5"/></svg>;
    case 'play.fill': return <svg {...common} fill="currentColor" stroke="none"><path d="M7 4.5v15l13-7.5L7 4.5Z"/></svg>;
    case 'download': return <svg {...common}><path d="M12 4v12M7 11l5 5 5-5M4 20h16"/></svg>;
    case 'share': return <svg {...common}><path d="M12 3v13M8 7l4-4 4 4"/><path d="M5 12v7a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-7"/></svg>;
    case 'star.fill': return <svg {...common} fill="currentColor" stroke="none"><path d="m12 3 2.7 5.7 6.3.9-4.6 4.4 1.1 6.2L12 17.3l-5.5 2.9 1.1-6.2-4.6-4.4 6.3-.9L12 3Z"/></svg>;
    case 'wifi': return <svg {...common}><path d="M2 8.5a16 16 0 0 1 20 0M5 12a11 11 0 0 1 14 0M8.5 15.5a6 6 0 0 1 7 0"/><circle cx="12" cy="19" r="1.2" fill="currentColor"/></svg>;
    case 'speedometer': return <svg {...common}><path d="M3 13a9 9 0 1 1 18 0"/><path d="M12 13l4.5-4.5"/><circle cx="12" cy="13" r="1.3" fill="currentColor"/></svg>;
    case 'tray': return <svg {...common}><path d="M3 14h4l1 2h8l1-2h4M4 14 6 5a1 1 0 0 1 1-.8h10a1 1 0 0 1 1 .8L20 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1Z"/></svg>;
    case 'film': return <svg {...common}><rect x="3.5" y="4" width="17" height="16" rx="2"/><path d="M7 4v16M17 4v16M3.5 9h3.5M17 9h3.5M3.5 15h3.5M17 15h3.5M7 12h10"/></svg>;
    case 'music': return <svg {...common}><path d="M9 18V6l11-2v12"/><circle cx="6" cy="18" r="2.5"/><circle cx="17" cy="16" r="2.5"/></svg>;
    case 'key': return <svg {...common}><circle cx="8" cy="15" r="3.5"/><path d="m10.5 12.5 8-8M15 8l3 3M13 10l2.5 2.5"/></svg>;
    case 'globe': return <svg {...common}><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/></svg>;
    case 'wand': return <svg {...common}><path d="m4 20 12-12M14 6l4 4M11 3l1 2M19 11l2 1M16 14l1 2M6 5l2 1"/></svg>;
    case 'arrow.up': return <svg {...common}><path d="M12 19V5M6 11l6-6 6 6"/></svg>;
    case 'rotate': return <svg {...common}><path d="M3 12a9 9 0 0 1 15.4-6.4L21 8M21 4v4h-4M21 12a9 9 0 0 1-15.4 6.4L3 16M3 20v-4h4"/></svg>;
    default: return <svg {...common}><rect x="4" y="4" width="16" height="16" rx="3"/></svg>;
  }
};

const BackendChip = ({ kind, size = 40, cryptOverlay = false }) => {
  const color = BACKEND_COLORS[kind] || BACKEND_COLORS.generic;
  const glyph = BACKEND_GLYPHS[kind] || 'cloud.fill';
  const r = size * 0.27;
  return (
    <div style={{ position:'relative', width:size+(cryptOverlay?4:0), height:size+(cryptOverlay?4:0) }}>
      <div style={{ width:size, height:size, borderRadius:r, background:color, color:'white',
        display:'flex', alignItems:'center', justifyContent:'center',
        boxShadow:`0 2px 4px ${color}33`, border:'0.5px solid rgba(255,255,255,0.18)' }}>
        <Icon name={glyph} size={size*0.5} weight="semibold"/>
      </div>
      {cryptOverlay && (
        <div style={{ position:'absolute', right:-2, bottom:-2, width:size*0.42, height:size*0.42,
          borderRadius:'50%', background:ACCENT, color:'white',
          display:'flex', alignItems:'center', justifyContent:'center', border:'2px solid white' }}>
          <Icon name="lock.fill" size={size*0.22} weight="bold"/>
        </div>
      )}
    </div>
  );
};
const CryptBadge = ({ size = 1 }) => (
  <span style={{ display:'inline-flex', alignItems:'center', gap:3*size, color:ACCENT, background:ACCENT_SOFT,
    padding:`${2*size}px ${5*size}px`, borderRadius:4*size, fontWeight:700, fontSize:10*size, letterSpacing:0.4*size }}>
    <Icon name="lock.fill" size={9*size} weight="bold"/>CRYPT
  </span>
);
const CryptSeal = ({ size = 120 }) => (
  <div style={{ position:'relative', width:size+6, height:size+6 }}>
    <div style={{ width:size, height:size, borderRadius:size*0.25,
      background:`linear-gradient(135deg, ${ACCENT}, ${ACCENT_DEEP})`,
      display:'flex', alignItems:'center', justifyContent:'center', color:'white',
      boxShadow:`0 14px 36px ${ACCENT}55, inset 0 0 0 1px rgba(255,255,255,0.25)` }}>
      <Icon name="lock.fill" size={size*0.5} weight="semibold"/>
    </div>
    <div style={{ position:'absolute', top:-size*0.04, right:-size*0.04, width:size*0.27, height:size*0.27,
      borderRadius:'50%', background:'#34C759', color:'white',
      display:'flex', alignItems:'center', justifyContent:'center', border:'3px solid white' }}>
      <Icon name="check" size={size*0.13} weight="bold"/>
    </div>
  </div>
);
const GradientAvatar = ({ initials, size = 48 }) => (
  <div style={{ width:size, height:size, borderRadius:'50%',
    background:`linear-gradient(135deg, ${ACCENT}, ${ACCENT_DEEP})`,
    display:'flex', alignItems:'center', justifyContent:'center', color:'white', fontWeight:600, fontSize:size*0.38 }}>
    {initials}
  </div>
);
const StatusBar = ({ scale = 1 }) => {
  const color = '#000';
  return (
    <div style={{ height:54*scale, padding:`0 ${44*scale}px`, display:'flex', alignItems:'center',
      justifyContent:'space-between', color, fontSize:17*scale, fontWeight:600,
      fontFamily:'-apple-system, "SF Pro Text", system-ui' }}>
      <span>9:41</span>
      <span style={{ display:'flex', alignItems:'center', gap:5*scale }}>
        <svg width={18*scale} height={11*scale} viewBox="0 0 18 11" fill={color}><rect x="0" y="7" width="3" height="4" rx="0.5"/><rect x="5" y="5" width="3" height="6" rx="0.5"/><rect x="10" y="2.5" width="3" height="8.5" rx="0.5"/><rect x="15" y="0" width="3" height="11" rx="0.5"/></svg>
        <svg width={17*scale} height={12*scale} viewBox="0 0 17 12" fill={color}><path d="M8.5 2.5c2.7 0 5.1 1 7 2.6l-1.3 1.6A8.5 8.5 0 0 0 8.5 5a8.5 8.5 0 0 0-5.7 2.1L1.5 5.5A11 11 0 0 1 8.5 2.5Zm0 3.5c1.8 0 3.5.7 4.7 1.8l-1.3 1.6c-.9-.8-2.1-1.4-3.4-1.4-1.3 0-2.5.6-3.4 1.4L3.8 7.8c1.2-1.1 2.9-1.8 4.7-1.8Zm0 3.5c1 0 1.8.4 2.4 1l-2.4 2.5-2.4-2.5c.6-.6 1.4-1 2.4-1Z"/></svg>
        <svg width={28*scale} height={12*scale} viewBox="0 0 28 12"><rect x="0.5" y="0.5" width="23" height="11" rx="2.5" fill="none" stroke={color} strokeOpacity="0.45"/><rect x="2" y="2" width="20" height="8" rx="1.5" fill={color}/><rect x="24.5" y="3.5" width="2.5" height="5" rx="1" fill={color} opacity="0.45"/></svg>
      </span>
    </div>
  );
};
const NavHeader = ({ title, scale = 1, trailing }) => (
  <div style={{ padding:`${4*scale}px ${20*scale}px ${14*scale}px`, display:'flex', alignItems:'flex-end', justifyContent:'space-between' }}>
    <h1 style={{ fontSize:34*scale, fontWeight:700, letterSpacing:-0.5*scale, margin:0, color:'#000' }}>{title}</h1>
    {trailing}
  </div>
);
const TabBar = ({ active = 'remotes', scale = 1 }) => {
  const t = useT();
  const items = [
    { id:'home', label:t('Accueil','Home'), icon:'sparkles' },
    { id:'remotes', label:t('Remotes','Remotes'), icon:'externaldrive' },
    { id:'transfers', label:t('Transferts','Transfers'), icon:'arrows' },
    { id:'settings', label:t('Réglages','Settings'), icon:'gear' },
  ];
  return (
    <div style={{ borderTop:'0.5px solid rgba(60,60,67,0.18)', background:'rgba(247,247,248,0.85)',
      backdropFilter:'blur(20px)', display:'flex', justifyContent:'space-around', padding:`${8*scale}px 0 ${28*scale}px` }}>
      {items.map(item => (
        <div key={item.id} style={{ display:'flex', flexDirection:'column', alignItems:'center', gap:2*scale,
          color:item.id===active ? ACCENT : '#8E8E93' }}>
          <Icon name={item.icon} size={26*scale} weight="regular"/>
          <span style={{ fontSize:10*scale, fontWeight:500 }}>{item.label}</span>
        </div>
      ))}
    </div>
  );
};
const ListRow = ({ leading, title, subtitle, trailing, scale = 1, divider = true }) => (
  <div style={{ display:'flex', alignItems:'center', gap:12*scale, padding:`${12*scale}px ${16*scale}px`,
    borderBottom:divider ? '0.5px solid rgba(60,60,67,0.18)' : 'none' }}>
    {leading}
    <div style={{ flex:1, minWidth:0 }}>
      <div style={{ fontSize:17*scale, fontWeight:500, color:'#000', display:'flex', alignItems:'center', gap:6*scale }}>{title}</div>
      {subtitle && <div style={{ fontSize:13*scale, color:'#8E8E93', marginTop:2*scale }}>{subtitle}</div>}
    </div>
    {trailing}
  </div>
);

/* ════════════════════════════════════════════════════════════════════
   8 écrans (440 × 956) — repris verbatim du handoff
   ════════════════════════════════════════════════════════════════════ */
const SCREEN_W = 440, SCREEN_H = 956;
const ScreenFrame = ({ children, bg = '#F2F2F7' }) => (
  <div style={{ width:SCREEN_W, height:SCREEN_H, background:bg, position:'relative', overflow:'hidden',
    fontFamily:'-apple-system, "SF Pro Text", system-ui, sans-serif', color:'#000', display:'flex', flexDirection:'column' }}>
    {children}
  </div>
);

const ScreenOnboarding = () => {
  const t = useT();
  return (
  <ScreenFrame bg="#FFFFFF">
    <StatusBar/>
    <div style={{ flex:1, display:'flex', flexDirection:'column', alignItems:'center', padding:'40px 28px 0' }}>
      <div style={{ marginTop:40 }}><CryptSeal size={132}/></div>
      <h1 style={{ fontSize:32, fontWeight:700, marginTop:28, marginBottom:6, letterSpacing:-0.6 }}>{t('Bienvenue dans Rclone','Welcome to Rclone')}</h1>
      <p style={{ fontSize:16, color:'#3C3C43', textAlign:'center', marginTop:18, lineHeight:1.4, maxWidth:340 }}>{t('Tous tes remotes — y compris chiffrés — accessibles depuis Fichiers, en streaming et hors-ligne.','All your remotes — encrypted ones included — right inside Files, streaming and offline.')}</p>
      <div style={{ marginTop:40, width:'100%', display:'flex', flexDirection:'column', gap:14 }}>
        {[
          { icon:'lock.fill', tint:ACCENT, title:t('Crypt rclone natif','Native rclone crypt'), sub:t('AES-256, noms déchiffrés à la volée','AES-256, filenames decrypted on the fly') },
          { icon:'cloud.fill', tint:'#1A73E8', title:t('80+ backends','80+ backends'), sub:'S3, R2, Drive, Dropbox, SFTP, B2…' },
          { icon:'folder.fill', tint:'#FF9500', title:t('Intégration Fichiers','Files integration'), sub:t('Chaque remote = un emplacement natif','Every remote = a native location') },
        ].map(f => (
          <div key={f.title} style={{ display:'flex', alignItems:'center', gap:14 }}>
            <div style={{ width:42, height:42, borderRadius:11, background:f.tint+'2E', color:f.tint, display:'flex', alignItems:'center', justifyContent:'center' }}><Icon name={f.icon} size={20} weight="semibold"/></div>
            <div style={{ flex:1 }}>
              <div style={{ fontSize:16, fontWeight:600 }}>{f.title}</div>
              <div style={{ fontSize:13, color:'#8E8E93', marginTop:1 }}>{f.sub}</div>
            </div>
          </div>
        ))}
      </div>
    </div>
    <div style={{ padding:'0 28px 36px' }}>
      <button style={{ width:'100%', padding:'15px 0', borderRadius:14, border:'none', background:ACCENT, color:'#fff', fontSize:17, fontWeight:600, boxShadow:`0 6px 18px ${ACCENT}55` }}>{t('Importer un rclone.conf','Import an rclone.conf')}</button>
      <button style={{ width:'100%', padding:'14px 0', borderRadius:14, border:'none', background:'transparent', color:ACCENT, fontSize:17, fontWeight:500, marginTop:6 }}>{t('Créer un Passeport Crypt','Create a Crypt Passport')}</button>
      <p style={{ textAlign:'center', fontSize:13, color:'#8E8E93', marginTop:8 }}>{t('Tes clés ne quittent jamais l\'iPhone','Your keys never leave the iPhone')}</p>
    </div>
  </ScreenFrame>);
};

const REMOTES = [
  { name:'photos-archive', sub:{fr:'Crypt sur B2',en:'Crypt on B2'}, chip:'b2', crypt:true },
  { name:'work-drive', sub:{fr:'Google Drive',en:'Google Drive'}, chip:'drive', crypt:false },
  { name:'backups-r2', sub:{fr:'Crypt sur Cloudflare R2',en:'Crypt on Cloudflare R2'}, chip:'s3', crypt:true },
  { name:'media', sub:{fr:'AWS S3 (eu-west-3)',en:'AWS S3 (eu-west-3)'}, chip:'s3', crypt:false },
  { name:'home-nas', sub:{fr:'SFTP — synology.local',en:'SFTP — synology.local'}, chip:'sftp', crypt:false },
  { name:'family-onedrive', sub:{fr:'Microsoft OneDrive',en:'Microsoft OneDrive'}, chip:'onedrive', crypt:false },
  { name:'archive-storj', sub:{fr:'Crypt sur Storj DCS',en:'Crypt on Storj DCS'}, chip:'storj', crypt:true },
  { name:'shared-dropbox', sub:{fr:'Dropbox',en:'Dropbox'}, chip:'dropbox', crypt:false },
];
const ScreenRemotes = () => {
  const t = useT();
  return (
  <ScreenFrame bg="#F2F2F7">
    <StatusBar/>
    <NavHeader title="Remotes" trailing={<div style={{ display:'flex', gap:18, color:ACCENT, paddingBottom:6 }}><Icon name="magnifying" size={22} weight="semibold"/><Icon name="plus" size={24} weight="semibold"/></div>}/>
    <div style={{ margin:'0 16px', background:'#fff', borderRadius:12, overflow:'hidden' }}>
      <div style={{ padding:'10px 16px 4px', fontSize:12, color:'#8E8E93', letterSpacing:0.4, textTransform:'uppercase' }}>{t('8 remotes · 3 chiffrés','8 remotes · 3 encrypted')}</div>
      {REMOTES.map((r, i) => (
        <ListRow key={r.name} divider={i < REMOTES.length-1}
          leading={<BackendChip kind={r.chip} cryptOverlay={r.crypt}/>}
          title={<><span>{r.name}</span>{r.crypt && <CryptBadge/>}</>}
          subtitle={t(r.sub.fr, r.sub.en)}
          trailing={<Icon name="chevron.right" size={14} weight="semibold" style={{ color:'#C7C7CC' }}/>}/>
      ))}
    </div>
    <div style={{ flex:1 }}/>
    <TabBar active="remotes"/>
  </ScreenFrame>);
};

const FILES = [
  { name:{fr:'Voyage Lisbonne 2024',en:'Lisbon Trip 2024'}, type:'folder', sub:{fr:'142 éléments',en:'142 items'}, state:null },
  { name:{fr:'Archive impôts 2023',en:'Tax Archive 2023'}, type:'folder', sub:{fr:'38 éléments',en:'38 items'}, state:null },
  { name:{fr:'Contrat-bail-2024.pdf',en:'Lease-2024.pdf'}, type:'doc', sub:{fr:'2,4 Mo · PDF',en:'2.4 MB · PDF'}, state:'local' },
  { name:{fr:'Présentation Q4.key',en:'Q4-Presentation.key'}, type:'doc', sub:{fr:'18,7 Mo · Keynote',en:'18.7 MB · Keynote'}, state:'downloading', progress:0.65 },
  { name:{fr:'IMG_4821.HEIC',en:'IMG_4821.HEIC'}, type:'photo', sub:{fr:'4,1 Mo · HEIC',en:'4.1 MB · HEIC'}, state:'cloud' },
  { name:{fr:'IMG_4822.HEIC',en:'IMG_4822.HEIC'}, type:'photo', sub:{fr:'3,8 Mo · HEIC',en:'3.8 MB · HEIC'}, state:'cloud' },
  { name:{fr:'sunset-timelapse.mov',en:'sunset-timelapse.mov'}, type:'film', sub:{fr:'342 Mo · MOV',en:'342 MB · MOV'}, state:'cloud' },
  { name:{fr:'piano-improv.m4a',en:'piano-improv.m4a'}, type:'music', sub:{fr:'8,2 Mo · M4A',en:'8.2 MB · M4A'}, state:'local' },
  { name:{fr:'rapport-annuel.docx',en:'annual-report.docx'}, type:'doc', sub:{fr:'1,1 Mo · DOCX',en:'1.1 MB · DOCX'}, state:'syncing' },
];
const FileTypeIcon = ({ type }) => {
  const map = { folder:{icon:'folder.fill',tint:'#1A73E8'}, doc:{icon:'doc',tint:'#8E8E93'},
    photo:{icon:'photo',tint:'#FF2D55'}, film:{icon:'film',tint:'#AF52DE'}, music:{icon:'music',tint:'#FF9500'} };
  const m = map[type] || map.doc;
  return <div style={{ width:36, height:36, borderRadius:9, background:m.tint+'20', color:m.tint, display:'flex', alignItems:'center', justifyContent:'center' }}><Icon name={m.icon} size={20} weight="semibold"/></div>;
};
const StateGlyph = ({ state, progress }) => {
  if (state === 'cloud') return <Icon name="cloud" size={16} style={{ color:'#8E8E93' }}/>;
  if (state === 'local') return <Icon name="check.circle" size={17} style={{ color:'#34C759' }}/>;
  if (state === 'syncing') return <Icon name="rotate" size={16} weight="semibold" style={{ color:'#1A73E8' }}/>;
  if (state === 'downloading') {
    const r = 8, c = 2*Math.PI*r;
    return (<svg width="20" height="20" viewBox="0 0 20 20"><circle cx="10" cy="10" r={r} fill="none" stroke="rgba(60,60,67,0.25)" strokeWidth="2"/><circle cx="10" cy="10" r={r} fill="none" stroke={ACCENT} strokeWidth="2" strokeDasharray={c} strokeDashoffset={c*(1-progress)} transform="rotate(-90 10 10)" strokeLinecap="round"/></svg>);
  }
  return null;
};
const ScreenFolder = () => {
  const t = useT();
  return (
  <ScreenFrame bg="#F2F2F7">
    <StatusBar/>
    <div style={{ padding:'6px 16px 8px', display:'flex', alignItems:'center', gap:6, color:ACCENT, fontSize:16, fontWeight:500 }}><Icon name="chevron.right" size={16} weight="semibold" style={{ transform:'rotate(180deg)' }}/><span>Remotes</span></div>
    <div style={{ padding:'4px 20px 4px' }}>
      <div style={{ display:'flex', alignItems:'center', gap:8 }}><BackendChip kind="b2" cryptOverlay={true} size={36}/><h1 style={{ fontSize:28, fontWeight:700, letterSpacing:-0.5, margin:0 }}>photos-archive</h1></div>
      <div style={{ marginTop:8, display:'flex', alignItems:'center', gap:6, fontSize:12, color:'#8E8E93', fontFamily:'ui-monospace, "SF Mono", monospace' }}><CryptBadge/><span style={{ overflow:'hidden', textOverflow:'ellipsis', whiteSpace:'nowrap' }}>photos-archive:/2024/Lisbon</span></div>
    </div>
    <div style={{ margin:'12px 16px 0', background:'#fff', borderRadius:12, overflow:'hidden' }}>
      {FILES.map((f, i) => (
        <ListRow key={f.name.en} divider={i < FILES.length-1}
          leading={<FileTypeIcon type={f.type}/>}
          title={t(f.name.fr, f.name.en)} subtitle={t(f.sub.fr, f.sub.en)}
          trailing={<div style={{ display:'flex', alignItems:'center', gap:10 }}><StateGlyph state={f.state} progress={f.progress}/><Icon name="chevron.right" size={14} weight="semibold" style={{ color:'#C7C7CC' }}/></div>}/>
      ))}
    </div>
    <div style={{ flex:1 }}/>
    <TabBar active="remotes"/>
  </ScreenFrame>);
};

const ScreenFileDetail = () => {
  const t = useT();
  return (
  <ScreenFrame bg="#F2F2F7">
    <StatusBar/>
    <div style={{ padding:'6px 16px 8px', display:'flex', alignItems:'center', gap:6, color:ACCENT, fontSize:16, fontWeight:500 }}><Icon name="chevron.right" size={16} weight="semibold" style={{ transform:'rotate(180deg)' }}/><span>{t('Lisbonne','Lisbon')}</span></div>
    <div style={{ margin:'4px 16px 0', borderRadius:16, overflow:'hidden', position:'relative', aspectRatio:'4/3' }}>
      <div style={{ position:'absolute', inset:0, background:'linear-gradient(135deg, #FFB088 0%, #FF6B6B 35%, #C44569 100%)' }}/>
      <div style={{ position:'absolute', inset:0, background:'radial-gradient(ellipse at 30% 80%, rgba(255,200,100,0.5), transparent 60%)' }}/>
      <div style={{ position:'absolute', bottom:0, left:0, right:0, height:'40%', background:'linear-gradient(transparent, rgba(0,0,0,0.45))' }}/>
      <div style={{ position:'absolute', bottom:12, left:14, right:14, display:'flex', alignItems:'center', justifyContent:'space-between', color:'#fff' }}>
        <div style={{ fontSize:13, fontWeight:600 }}>sunset-belem.jpg</div>
        <div style={{ padding:'4px 8px', background:'rgba(255,255,255,0.22)', backdropFilter:'blur(10px)', borderRadius:6, fontSize:11, fontWeight:700, letterSpacing:0.4 }}>4032 × 3024</div>
      </div>
    </div>
    <div style={{ padding:'14px 20px 4px' }}>
      <div style={{ display:'flex', alignItems:'center', gap:8, flexWrap:'wrap' }}><h1 style={{ fontSize:24, fontWeight:700, margin:0, letterSpacing:-0.4 }}>sunset-belem.jpg</h1><CryptBadge/></div>
      <div style={{ marginTop:4, fontSize:13, color:'#8E8E93' }}>{t('4,1 Mo · HEIC · modifié il y a 2h','4.1 MB · HEIC · edited 2h ago')}</div>
    </div>
    <div style={{ padding:'16px 16px 0', display:'grid', gridTemplateColumns:'repeat(4, 1fr)', gap:8 }}>
      {[
        { title:t('Ouvrir','Open'), icon:'play.fill', primary:true },
        { title:t('Télécharger','Download'), icon:'download', primary:false },
        { title:t('Partager','Share'), icon:'share', primary:false },
        { title:t('Favori','Favorite'), icon:'star.fill', primary:false },
      ].map(a => (
        <button key={a.title} style={{ padding:'14px 6px 12px', borderRadius:12,
          background:a.primary ? ACCENT : 'rgba(255,255,255,0.85)', color:a.primary ? '#fff' : ACCENT,
          border:a.primary ? 'none' : '0.5px solid rgba(60,60,67,0.18)',
          display:'flex', flexDirection:'column', alignItems:'center', gap:6,
          boxShadow:a.primary ? `0 4px 12px ${ACCENT}40` : 'none' }}>
          <Icon name={a.icon} size={22} weight="semibold"/>
          <span style={{ fontSize:11, fontWeight:600, color:a.primary ? '#fff' : '#000' }}>{a.title}</span>
        </button>
      ))}
    </div>
    <div style={{ margin:'16px 16px 0', background:'#fff', borderRadius:12, padding:'14px 16px' }}>
      <div style={{ fontSize:12, color:'#8E8E93', letterSpacing:0.4, textTransform:'uppercase', marginBottom:8 }}>{t('Sécurité & intégrité','Security & integrity')}</div>
      {[
        { k:t('Chiffrement','Encryption'), v:'NaCl secretbox (XSalsa20-Poly1305)' },
        { k:'SHA-256', v:'7f3a · b2d8 · 9e1c · 4a52', mono:true },
        { k:t('Stockage','Storage'), v:'b2://photos-archive-crypt/2024…' },
        { k:'TLS', v:t('TLS 1.3 · ATS strict','TLS 1.3 · strict ATS'), last:true },
      ].map((r) => (
        <div key={r.k} style={{ display:'flex', justifyContent:'space-between', alignItems:'center', padding:'6px 0', borderBottom:r.last ? 'none' : '0.5px solid rgba(60,60,67,0.12)' }}>
          <div style={{ fontSize:14, color:'#8E8E93' }}>{r.k}</div>
          <div style={{ fontSize:13, color:'#000', textAlign:'right', fontFamily:r.mono ? 'ui-monospace, "SF Mono", monospace' : 'inherit' }}>{r.v}</div>
        </div>
      ))}
    </div>
    <div style={{ flex:1 }}/>
    <TabBar active="remotes"/>
  </ScreenFrame>);
};

const ScreenHome = () => {
  const t = useT();
  return (
  <ScreenFrame bg="#F2F2F7">
    <StatusBar/>
    <NavHeader title={t('Accueil','Home')} trailing={<Icon name="rotate" size={22} weight="semibold" style={{ color:ACCENT, paddingBottom:8 }}/>}/>
    <div style={{ margin:'0 16px', borderRadius:16, padding:18, background:`linear-gradient(135deg, ${ACCENT} 0%, ${ACCENT_DEEP} 100%)`, color:'#fff', boxShadow:`0 10px 24px ${ACCENT}40` }}>
      <div style={{ display:'flex', alignItems:'center', gap:10 }}>
        <div style={{ width:36, height:36, borderRadius:10, background:'rgba(255,255,255,0.18)', display:'flex', alignItems:'center', justifyContent:'center' }}><Icon name="bolt.fill" size={20}/></div>
        <div><div style={{ fontSize:18, fontWeight:700 }}>{t('Transferts en cours','Active transfers')}</div><div style={{ fontSize:13, opacity:0.9, marginTop:1 }}>{t('3 opérations actives sur 8 remotes','3 active operations across 8 remotes')}</div></div>
      </div>
      <div style={{ display:'grid', gridTemplateColumns:'repeat(2, 1fr)', gap:8, marginTop:14 }}>
        {[
          { v:'8', l:t('remotes','remotes'), i:'externaldrive' },
          { v:'3', l:t('actifs','active'), i:'bolt.fill' },
          { v:'142', l:t('photos sync','photos sync'), i:'photo' },
          { v:t('4,2 Go','4.2 GB'), l:t('cache','cache'), i:'tray' },
        ].map(m => (
          <div key={m.l} style={{ background:'rgba(255,255,255,0.14)', borderRadius:10, padding:'10px 12px', display:'flex', alignItems:'center', gap:10 }}>
            <Icon name={m.i} size={18}/><div><div style={{ fontSize:18, fontWeight:700 }}>{m.v}</div><div style={{ fontSize:11, opacity:0.85 }}>{m.l}</div></div>
          </div>
        ))}
      </div>
    </div>
    <div style={{ margin:'18px 16px 0' }}>
      <div style={{ fontSize:13, color:'#8E8E93', letterSpacing:0.4, textTransform:'uppercase', padding:'0 4px 8px' }}>{t('Actions rapides','Quick actions')}</div>
      <div style={{ display:'grid', gridTemplateColumns:'repeat(3, 1fr)', gap:10 }}>
        {[
          { t:t('Nouveau','New'), s:t('Ajouter remote','Add remote'), i:'plus.circle', c:'#1A73E8' },
          { t:t('Importer','Import'), s:'rclone.conf', i:'download', c:'#34C759' },
          { t:t('Photos','Photos'), s:t('142 en attente','142 pending'), i:'photo.stack', c:'#FF2D55' },
        ].map(a => (
          <div key={a.t} style={{ background:'#fff', borderRadius:12, padding:12, border:'0.5px solid rgba(60,60,67,0.1)' }}>
            <div style={{ width:32, height:32, borderRadius:8, background:a.c+'22', color:a.c, display:'flex', alignItems:'center', justifyContent:'center' }}><Icon name={a.i} size={18} weight="semibold"/></div>
            <div style={{ marginTop:8, fontSize:14, fontWeight:600 }}>{a.t}</div><div style={{ fontSize:11, color:'#8E8E93', marginTop:1 }}>{a.s}</div>
          </div>
        ))}
      </div>
    </div>
    <div style={{ margin:'18px 16px 0' }}>
      <div style={{ fontSize:13, color:'#8E8E93', letterSpacing:0.4, textTransform:'uppercase', padding:'0 4px 8px' }}>{t('Récents','Recents')}</div>
      <div style={{ background:'#fff', borderRadius:12, overflow:'hidden' }}>
        {[
          { n:t('Voyage Lisbonne 2024','Lisbon Trip 2024'), s:'photos-archive', tm:t('il y a 3 min','3 min ago'), chip:'b2', crypt:true },
          { n:t('Présentation Q4','Q4 Presentation'), s:'work-drive', tm:t('il y a 1 h','1 h ago'), chip:'drive', crypt:false },
          { n:t('Backups système','System backups'), s:'backups-r2', tm:t('hier','yesterday'), chip:'s3', crypt:true },
        ].map((r, i, arr) => (
          <ListRow key={r.n} divider={i < arr.length-1}
            leading={<BackendChip kind={r.chip} cryptOverlay={r.crypt} size={32}/>}
            title={r.n} subtitle={r.s}
            trailing={<span style={{ fontSize:12, color:'#8E8E93' }}>{r.tm}</span>}/>
        ))}
      </div>
    </div>
    <div style={{ flex:1 }}/>
    <TabBar active="home"/>
  </ScreenFrame>);
};

const WIZARD_BACKENDS = [
  { k:'s3', label:'Amazon S3' }, { k:'b2', label:'Backblaze B2' }, { k:'drive', label:'Google Drive' },
  { k:'dropbox', label:'Dropbox' }, { k:'onedrive', label:'OneDrive' }, { k:'box', label:'Box' },
  { k:'sftp', label:'SFTP' }, { k:'webdav', label:'WebDAV' }, { k:'crypt', label:'Crypt' },
  { k:'storj', label:'Storj DCS' }, { k:'wasabi', label:'Wasabi' }, { k:'pcloud', label:'pCloud' },
];
const ScreenWizard = () => {
  const t = useT();
  return (
  <ScreenFrame bg="#F2F2F7">
    <StatusBar/>
    <div style={{ height:22, display:'flex', justifyContent:'center', alignItems:'flex-end', paddingBottom:8 }}><div style={{ width:36, height:5, borderRadius:3, background:'rgba(60,60,67,0.3)' }}/></div>
    <div style={{ display:'flex', justifyContent:'space-between', padding:'0 16px 4px', color:ACCENT, fontSize:16 }}><span style={{ fontWeight:500 }}>{t('Annuler','Cancel')}</span><span style={{ fontWeight:600, color:'#000', fontSize:17 }}>{t('Nouveau remote','New remote')}</span><span style={{ opacity:0.4 }}>{t('Suivant','Next')}</span></div>
    <div style={{ padding:'14px 20px 0', display:'flex', alignItems:'center', gap:6 }}>{[1,2,3,4].map(s => <div key={s} style={{ flex:1, height:4, borderRadius:2, background:s===1 ? ACCENT : 'rgba(60,60,67,0.18)' }}/>)}</div>
    <div style={{ padding:'10px 20px 0', fontSize:12, color:'#8E8E93', letterSpacing:0.4, textTransform:'uppercase' }}>{t('Étape 1 sur 4 — Choisir un backend','Step 1 of 4 — Choose a backend')}</div>
    <div style={{ padding:'12px 20px 0' }}>
      <h2 style={{ fontSize:22, fontWeight:700, margin:0, letterSpacing:-0.4 }}>{t('Quel stockage veux-tu connecter ?','Which storage do you want to connect?')}</h2>
      <p style={{ fontSize:14, color:'#8E8E93', marginTop:4 }}>{t('70+ services pris en charge. OAuth en 2 tapotements.','70+ services supported. OAuth in 2 taps.')}</p>
    </div>
    <div style={{ margin:'14px 20px 0', display:'flex', alignItems:'center', gap:8, background:'rgba(118,118,128,0.12)', borderRadius:10, padding:'8px 12px' }}><Icon name="magnifying" size={16} style={{ color:'#8E8E93' }}/><span style={{ fontSize:15, color:'#8E8E93' }}>{t('Rechercher un backend','Search a backend')}</span></div>
    <div style={{ padding:'14px 20px 0', display:'grid', gridTemplateColumns:'repeat(3, 1fr)', gap:10 }}>
      {WIZARD_BACKENDS.map(b => (
        <div key={b.k} style={{ background:'#fff', borderRadius:14, padding:'14px 8px', display:'flex', flexDirection:'column', alignItems:'center', gap:8, border:b.k==='crypt' ? `1.5px solid ${ACCENT}` : '0.5px solid rgba(60,60,67,0.1)', boxShadow:b.k==='crypt' ? `0 4px 14px ${ACCENT}25` : 'none' }}>
          <BackendChip kind={b.k} size={44}/>
          <div style={{ fontSize:12, fontWeight:600, textAlign:'center', lineHeight:1.2 }}>{b.label}</div>
          {b.k==='crypt' && <div style={{ position:'relative', marginTop:-4, fontSize:9, fontWeight:700, letterSpacing:0.4, color:ACCENT, padding:'2px 6px', background:ACCENT_SOFT, borderRadius:4 }}>{t('RECOMMANDÉ','RECOMMENDED')}</div>}
        </div>
      ))}
    </div>
    <div style={{ flex:1 }}/>
    <div style={{ padding:'0 20px 28px' }}><div style={{ fontSize:12, color:'#8E8E93', textAlign:'center' }}>{t('Ou ','Or ')}<span style={{ color:ACCENT, fontWeight:600 }}>{t('importer un rclone.conf existant','import an existing rclone.conf')}</span></div></div>
  </ScreenFrame>);
};

const ScreenPhotoSync = () => {
  const t = useT();
  return (
  <ScreenFrame bg="#F2F2F7">
    <StatusBar/>
    <div style={{ padding:'6px 16px 8px', display:'flex', alignItems:'center', gap:6, color:ACCENT, fontSize:16, fontWeight:500 }}><Icon name="chevron.right" size={16} weight="semibold" style={{ transform:'rotate(180deg)' }}/><span>{t('Réglages','Settings')}</span></div>
    <NavHeader title={t('Sync Photos','Photo Sync')} trailing={null}/>
    <div style={{ margin:'0 16px', borderRadius:16, padding:16, background:'linear-gradient(135deg, #FF2D55 0%, #C44569 100%)', color:'#fff', boxShadow:'0 10px 24px rgba(255,45,85,0.30)' }}>
      <div style={{ display:'flex', alignItems:'center', gap:12 }}>
        <Icon name="photo.stack" size={28}/>
        <div style={{ flex:1 }}><div style={{ fontSize:16, fontWeight:700 }}>{t('Sauvegarde active','Backup active')}</div><div style={{ fontSize:12, opacity:0.9, marginTop:1 }}>{t('Vers photos-archive · chiffré','To photos-archive · encrypted')}</div></div>
        <div style={{ width:48, height:28, borderRadius:14, background:'rgba(255,255,255,0.35)', padding:2, display:'flex', justifyContent:'flex-end' }}><div style={{ width:24, height:24, borderRadius:'50%', background:'#fff' }}/></div>
      </div>
      <div style={{ marginTop:16 }}>
        <div style={{ display:'flex', justifyContent:'space-between', fontSize:12, marginBottom:6 }}><span>{t('2 418 / 2 560 médias','2,418 / 2,560 items')}</span><span style={{ fontWeight:600 }}>94 %</span></div>
        <div style={{ height:6, borderRadius:3, background:'rgba(255,255,255,0.25)' }}><div style={{ width:'94%', height:'100%', borderRadius:3, background:'#fff' }}/></div>
      </div>
    </div>
    <div style={{ padding:'14px 16px 0', display:'grid', gridTemplateColumns:'repeat(3, 1fr)', gap:8 }}>
      {[
        { v:'2 418', l:t('sauvegardées','backed up'), i:'check.circle', c:'#34C759' },
        { v:'142', l:t('en attente','pending'), i:'clock', c:'#FF9500' },
        { v:t('38 Go','38 GB'), l:t('transférés','transferred'), i:'arrow.up', c:'#1A73E8' },
      ].map(s => (
        <div key={s.l} style={{ background:'#fff', borderRadius:12, padding:12 }}><Icon name={s.i} size={18} style={{ color:s.c }}/><div style={{ fontSize:18, fontWeight:700, marginTop:6 }}>{s.v}</div><div style={{ fontSize:11, color:'#8E8E93', marginTop:1 }}>{s.l}</div></div>
      ))}
    </div>
    <div style={{ padding:'8px 16px 0', fontSize:13, color:'#8E8E93', letterSpacing:0.4, textTransform:'uppercase', marginTop:14 }}>{t('Conditions','Conditions')}</div>
    <div style={{ margin:'6px 16px 0', background:'#fff', borderRadius:12, overflow:'hidden' }}>
      {[
        { i:'wifi', t:t('Wi-Fi uniquement','Wi-Fi only'), s:t('Pas de cellulaire','No cellular'), on:true },
        { i:'bolt.fill', t:t('Charger en priorité','Charge priority'), s:t('Quand branché','When plugged in'), on:true },
        { i:'speedometer', t:t('Débit adaptatif','Adaptive throughput'), s:t('8 Mo/s actif · 80 Mo/s veille','8 MB/s active · 80 MB/s idle'), on:true },
      ].map((opt, i, arr) => (
        <ListRow key={opt.t} divider={i < arr.length-1}
          leading={<div style={{ width:30, height:30, borderRadius:8, background:ACCENT_SOFT, color:ACCENT, display:'flex', alignItems:'center', justifyContent:'center' }}><Icon name={opt.i} size={16} weight="semibold"/></div>}
          title={opt.t} subtitle={opt.s}
          trailing={<div style={{ width:50, height:30, borderRadius:15, background:opt.on ? '#34C759' : '#E5E5EA', padding:2, display:'flex', justifyContent:opt.on ? 'flex-end' : 'flex-start' }}><div style={{ width:26, height:26, borderRadius:'50%', background:'#fff', boxShadow:'0 2px 4px rgba(0,0,0,0.2)' }}/></div>}/>
      ))}
    </div>
    <div style={{ flex:1 }}/>
    <TabBar active="settings"/>
  </ScreenFrame>);
};

const ScreenSecurity = () => {
  const t = useT();
  return (
  <ScreenFrame bg="#F2F2F7">
    <StatusBar/>
    <div style={{ padding:'6px 16px 8px', display:'flex', alignItems:'center', gap:6, color:ACCENT, fontSize:16, fontWeight:500 }}><Icon name="chevron.right" size={16} weight="semibold" style={{ transform:'rotate(180deg)' }}/><span>{t('Réglages','Settings')}</span></div>
    <NavHeader title={t('Sécurité','Security')}/>
    <div style={{ padding:'4px 24px 0', display:'flex', flexDirection:'column', alignItems:'center', textAlign:'center' }}>
      <CryptSeal size={104}/>
      <h2 style={{ fontSize:22, fontWeight:700, margin:'20px 0 6px', letterSpacing:-0.3 }}>{t('Tes clés ne quittent pas l\'iPhone','Your keys never leave the iPhone')}</h2>
      <p style={{ fontSize:14, color:'#3C3C43', margin:0, maxWidth:320, lineHeight:1.4 }}>{t('Configuration chiffrée au repos · ChaCha20-Poly1305 · OAuth dans le Trousseau iOS.','Config encrypted at rest · ChaCha20-Poly1305 · OAuth in the iOS Keychain.')}</p>
    </div>
    <div style={{ margin:'20px 16px 0', background:'#fff', borderRadius:12, overflow:'hidden' }}>
      {[
        { i:'faceid', t:'Face ID', s:t('Verrouiller au lancement','Lock on launch'), on:true },
        { i:'lock.fill', t:t('Verrouillage immédiat','Instant lock'), s:t('Dès retour à l\'écran d\'accueil','On return to Home Screen'), on:true },
        { i:'key', t:t('Trousseau iOS','iOS Keychain'), s:t('4 jetons OAuth protégés','4 protected OAuth tokens'), chev:true },
      ].map((opt, i, arr) => (
        <ListRow key={opt.t} divider={i < arr.length-1}
          leading={<div style={{ width:30, height:30, borderRadius:8, background:ACCENT_SOFT, color:ACCENT, display:'flex', alignItems:'center', justifyContent:'center' }}><Icon name={opt.i} size={16} weight="semibold"/></div>}
          title={opt.t} subtitle={opt.s}
          trailing={opt.chev ? <Icon name="chevron.right" size={14} weight="semibold" style={{ color:'#C7C7CC' }}/> : <div style={{ width:50, height:30, borderRadius:15, background:opt.on ? '#34C759' : '#E5E5EA', padding:2, display:'flex', justifyContent:opt.on ? 'flex-end' : 'flex-start' }}><div style={{ width:26, height:26, borderRadius:'50%', background:'#fff', boxShadow:'0 2px 4px rgba(0,0,0,0.2)' }}/></div>}/>
      ))}
    </div>
    <div style={{ padding:'20px 16px 0', fontSize:13, color:'#8E8E93', letterSpacing:0.4, textTransform:'uppercase' }}>{t('Garanties confidentialité','Privacy guarantees')}</div>
    <div style={{ margin:'6px 16px 0', background:'#fff', borderRadius:12, padding:'6px 14px' }}>
      {[
        t('Aucune analytics, aucun tracker','No analytics, no trackers'),
        t('Aucun serveur backend tiers','No third-party backend server'),
        t('ATS strict — TLS 1.3 partout','Strict ATS — TLS 1.3 everywhere'),
        t('Open source · auditable sur GitHub','Open source · auditable on GitHub'),
      ].map((line, i, arr) => (
        <div key={line} style={{ display:'flex', alignItems:'center', gap:12, padding:'12px 0', borderBottom:i < arr.length-1 ? '0.5px solid rgba(60,60,67,0.12)' : 'none' }}><Icon name="check.circle" size={20} style={{ color:'#34C759' }}/><span style={{ fontSize:15 }}>{line}</span></div>
      ))}
    </div>
    <div style={{ flex:1 }}/>
    <TabBar active="settings"/>
  </ScreenFrame>);
};

/* ════════════════════════════════════════════════════════════════════
   Shots (palettes + headlines repris de app.jsx)
   ════════════════════════════════════════════════════════════════════ */
const PALETTES = {
  violet:   { from:'#F4EEFE', to:'#E8DCFA', accent:ACCENT,    deep:ACCENT_DEEP },
  cream:    { from:'#FBF7EE', to:'#F2E7CC', accent:'#7C3AED', deep:'#5B21B6' },
  midnight: { from:'#1A1530', to:'#0E0820', accent:'#A78BFA', deep:'#7C3AED', dark:true },
  ocean:    { from:'#E6F0FB', to:'#CFE0F4', accent:'#0E5FAE', deep:'#093E70' },
  forest:   { from:'#E7F2EC', to:'#CFE5D7', accent:'#1F8F4A', deep:'#136230' },
  rose:     { from:'#FBECEF', to:'#F4D5DC', accent:'#C44569', deep:'#8A2842' },
};
const SHOTS = [
  { id:'crypt-first', Screen:ScreenOnboarding, palette:'violet', fr:{h:'Tous vos clouds.\nChiffrés.', s:'rclone crypt natif. Vos clés ne quittent jamais l\'iPhone.'}, en:{h:'Every cloud.\nEncrypted.', s:'Native rclone crypt. Your keys never leave the iPhone.'} },
  { id:'backends', Screen:ScreenRemotes, palette:'ocean', fr:{h:'80+ services.\nUn seul endroit.', s:'S3, R2, Drive, Dropbox, B2, SFTP, WebDAV, Storj, Wasabi…'}, en:{h:'80+ services.\nOne home.', s:'S3, R2, Drive, Dropbox, B2, SFTP, WebDAV, Storj, Wasabi…'} },
  { id:'crypt-paths', Screen:ScreenFolder, palette:'violet', fr:{h:'Noms déchiffrés\nà la volée.', s:'Aucun transit en clair. AES-256 + NaCl secretbox.'}, en:{h:'Filenames decrypted\non the fly.', s:'No cleartext in transit. AES-256 + NaCl secretbox.'} },
  { id:'stream', Screen:ScreenFileDetail, palette:'rose', fr:{h:'Stream direct.\nZéro téléchargement.', s:'Photos, vidéos, PDF — ouverts depuis Fichiers iOS.'}, en:{h:'Stream direct.\nNo full download.', s:'Photos, video, PDF — opened straight from Files.'} },
  { id:'home', Screen:ScreenHome, palette:'cream', fr:{h:'Votre centre\nde contrôle.', s:'Transferts, favoris, sync photo, débit. En un coup d\'œil.'}, en:{h:'Your control\ncenter.', s:'Transfers, pins, photo sync, throughput. At a glance.'} },
  { id:'wizard', Screen:ScreenWizard, palette:'forest', fr:{h:'Assistant\nguidé.', s:'OAuth en deux tapotements. Import rclone.conf en un geste.'}, en:{h:'Guided\nsetup.', s:'OAuth in two taps. rclone.conf import in one gesture.'} },
  { id:'photos', Screen:ScreenPhotoSync, palette:'rose', fr:{h:'Backup photo,\nintelligent.', s:'Throttle adaptatif, reprise réseau, exécution en arrière-plan.'}, en:{h:'Smart photo\nbackup.', s:'Adaptive throttle, network resume, background tasks.'} },
  { id:'privacy', Screen:ScreenSecurity, palette:'midnight', fr:{h:'Zéro tracker.\nZéro serveur.', s:'Aucune analytics. Open source. ATS strict, TLS 1.3 partout.'}, en:{h:'Zero trackers.\nZero servers.', s:'No analytics. Open source. Strict ATS, TLS 1.3 everywhere.'} },
];

/* ════════════════════════════════════════════════════════════════════
   Landing page
   ════════════════════════════════════════════════════════════════════ */
const ML = (s) => s.split('\n').map((l, i, a) => <React.Fragment key={i}>{l}{i < a.length-1 && <br/>}</React.Fragment>);

const AppleLogo = () => (
  <svg viewBox="0 0 24 24" fill="currentColor"><path d="M16.37 1.43c0 1.14-.42 2.2-1.12 2.98-.85.95-2.22 1.68-3.36 1.59-.14-1.12.44-2.29 1.11-3.02C13.76 2.13 15.16 1.42 16.37 1.43Zm4.1 15.83c-.55 1.27-.81 1.84-1.52 2.96-.99 1.56-2.38 3.49-4.11 3.51-1.53.02-1.93-1-4.01-.99-2.08.01-2.52 1.01-4.05.99-1.73-.02-3.05-1.77-4.04-3.33-2.76-4.34-3.05-9.43-1.35-12.13 1.21-1.92 3.12-3.04 4.92-3.04 1.83 0 2.98 1 4.49 1 1.47 0 2.36-1 4.48-1 1.6 0 3.3.87 4.51 2.38-3.96 2.17-3.32 7.82.68 9.65Z"/></svg>
);

const AppStoreBadge = () => {
  const t = useT();
  return (
    <a className="appstore" href={APP_STORE_URL} target="_blank" rel="noopener">
      <AppleLogo/>
      <span><span className="l1">{t('Télécharger sur l\'','Download on the')}</span><span className="l2">App Store</span></span>
    </a>
  );
};

const Header = ({ lang, setLang }) => (
  <header className="nav">
    <div className="wrap nav-in">
      <a className="brand" href="#top"><img src="icon.png" alt="Rclone GUI"/>Rclone GUI</a>
      <div className="nav-sp"/>
      <a className="ghost" href={GITHUB_URL} target="_blank" rel="noopener" style={{ marginRight:6 }}>GitHub</a>
      <div className="lang">
        <button className={lang==='en'?'on':''} onClick={() => setLang('en')}>EN</button>
        <button className={lang==='fr'?'on':''} onClick={() => setLang('fr')}>FR</button>
      </div>
    </div>
  </header>
);

const Hero = () => {
  const t = useT();
  return (
    <section className="hero" id="top">
      <div className="wrap">
        <img className="icon" src="icon.png" alt="Rclone GUI"/>
        <div><span className="pill"><Icon name="bolt.fill" size={14}/>{t('1 MOIS OFFERT','1 MONTH FREE')}</span></div>
        <h1 className="title">{ML(t('Tous vos clouds.\nChiffrés.','Every cloud.\nEncrypted.'))}</h1>
        <p className="sub">{t('Parcourez 80+ services cloud — y compris vos remotes rclone chiffrés — directement dans Fichiers. iPhone, iPad & Mac.','Browse 80+ cloud services — including your encrypted rclone crypt remotes — right inside Files. iPhone, iPad & Mac.')}</p>
        <div className="cta-row">
          <a className="btn btn-violet" href="#free"><Icon name="bolt.fill" size={18}/>{t('Obtenir mon mois gratuit','Get my free month')}</a>
          <AppStoreBadge/>
        </div>
        <div className="trust">
          <span><Icon name="lock.fill" size={15} style={{ color:ACCENT }}/>{t('Chiffrement de bout en bout','End-to-end crypt')}</span>
          <span><Icon name="shield.fill" size={15} style={{ color:ACCENT }}/>{t('Zéro tracker','Zero trackers')}</span>
          <span><Icon name="check.circle" size={15} style={{ color:ACCENT }}/>{t('Open source','Open source')}</span>
        </div>
      </div>
    </section>
  );
};

const PhoneFrame = ({ Screen, w = 270 }) => {
  const scale = w / SCREEN_W;
  const h = SCREEN_H * scale;
  return (
    <div className="phone" style={{ width:w+14, height:h+14 }}>
      <div className="phone-island"/>
      <div className="phone-screen" style={{ width:w, height:h }}>
        <div style={{ width:SCREEN_W, height:SCREEN_H, transform:`scale(${scale})`, transformOrigin:'top left' }}><Screen/></div>
      </div>
    </div>
  );
};

const Gallery = ({ lang }) => {
  const t = useT();
  return (
    <section id="screens">
      <div className="wrap">
        <div className="eyebrow">{t('Aperçu','Take a look')}</div>
        <h2 className="sec">{t('Comme dans Fichiers. En mieux.','Just like Files. Only better.')}</h2>
        <p className="sec-sub">{t('Faites défiler les écrans de l\'app — chiffrement, 80+ services, streaming, sauvegarde photo.','Swipe through the app — encryption, 80+ services, streaming, photo backup.')}</p>
      </div>
      <div className="gallery">
        {SHOTS.map(s => {
          const p = PALETTES[s.palette];
          const copy = s[lang] || s.en;
          const ink = p.dark ? '#fff' : '#0B0820';
          return (
            <div key={s.id} className="panel" style={{ background:`linear-gradient(180deg, ${p.from} 0%, ${p.to} 100%)`, color:ink }}>
              <div className="kick" style={{ color:p.accent }}>RCLONE GUI · iOS</div>
              <h3>{ML(copy.h)}</h3>
              <p className="psub">{copy.s}</p>
              <div className="stage"><PhoneFrame Screen={s.Screen}/></div>
            </div>
          );
        })}
      </div>
    </section>
  );
};

const Features = () => {
  const t = useT();
  const feats = [
    { i:'lock.fill', c:ACCENT, t:t('Crypt rclone natif','Native rclone crypt'), d:t('AES-256 + NaCl secretbox. Vos clés ne quittent jamais l\'appareil.','AES-256 + NaCl secretbox. Your keys never leave the device.') },
    { i:'cloud.fill', c:'#1A73E8', t:t('80+ services','80+ services'), d:'S3, R2, Drive, Dropbox, B2, SFTP, WebDAV, Storj, Wasabi…' },
    { i:'play.fill', c:'#C44569', t:t('Streaming direct','Direct streaming'), d:t('Photos, vidéos et PDF ouverts sans tout télécharger.','Photos, video and PDF opened without a full download.') },
    { i:'photo.stack', c:'#FF2D55', t:t('Backup photo intelligent','Smart photo backup'), d:t('Débit adaptatif, reprise réseau, exécution en arrière-plan.','Adaptive throughput, network resume, background tasks.') },
    { i:'wand', c:'#1F8F4A', t:t('Assistant guidé','Guided setup'), d:t('OAuth en deux tapotements. Import rclone.conf en un geste.','OAuth in two taps. rclone.conf import in one gesture.') },
    { i:'shield.fill', c:'#5B21B6', t:t('Zéro tracker, open source','Zero trackers, open source'), d:t('Aucune analytics, aucun serveur tiers. Auditable sur GitHub.','No analytics, no third-party server. Auditable on GitHub.') },
  ];
  return (
    <section id="features">
      <div className="wrap">
        <div className="eyebrow">{t('Fonctionnalités','Features')}</div>
        <h2 className="sec">{t('Pensé pour la confidentialité','Built for privacy')}</h2>
        <div className="grid">
          {feats.map(f => (
            <div key={f.t} className="card">
              <div className="ic" style={{ background:`linear-gradient(135deg, ${f.c}, ${f.c}cc)` }}><Icon name={f.i} size={24} weight="semibold"/></div>
              <h4>{f.t}</h4><p>{f.d}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
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
      if (saved && saved.code) { setCode(saved.code); setUrl(saved.url); setState('done'); }
    } catch (e) {}
  }, []);

  const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
  const claim = async () => {
    const mail = email.trim().toLowerCase();
    if (!EMAIL_RE.test(mail)) { setEmailErr(true); return; }
    setEmailErr(false);
    setState('loading');
    try {
      const res = await fetch(CLAIM_API, {
        method:'POST',
        headers:{ 'Content-Type':'application/json' },
        body: JSON.stringify({ email: mail, newsletter, lang }),
      });
      const data = await res.json().catch(() => ({}));
      if (res.ok && data.sent) {
        setState('sent');
      } else if (res.ok && data.code) {
        setCode(data.code); setUrl(data.url);
        try { localStorage.setItem(STORE_KEY, JSON.stringify({ code:data.code, url:data.url })); } catch (e) {}
        setState('done');
      } else if (res.status === 400 || data.error === 'invalid_email') {
        setEmailErr(true); setState('idle');
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
    try { await navigator.clipboard.writeText(code); setCopied(true); setTimeout(() => setCopied(false), 1800); } catch (e) {}
  };

  return (
    <section id="free">
      <div className="wrap">
        <div className="free">
          <div className="gift">🎁</div>
          <h2>{t('Un mois offert','One month free')}</h2>
          <p className="lede">{t('Un code App Store personnel, valable une fois, pour démarrer votre essai sans frais. Un par personne.','A personal, single-use App Store code to start your trial at no cost. One per person.')}</p>

          <div className="claimbox">
            {state === 'idle' && (
              <div>
                <input className="field" type="email" inputMode="email" autoComplete="email"
                  placeholder={t('Votre adresse e-mail','Your email address')}
                  value={email}
                  onChange={e => { setEmail(e.target.value); if (emailErr) setEmailErr(false); }}
                  onKeyDown={e => { if (e.key === 'Enter') claim(); }}
                  style={emailErr ? { borderColor:'#fff', boxShadow:'0 0 0 3px rgba(255,255,255,.55)' } : null}/>
                {emailErr && <p className="mini" style={{ marginTop:8, fontWeight:700 }}>{t('Entrez une adresse e-mail valide.','Please enter a valid email address.')}</p>}
                <label className="optin">
                  <input type="checkbox" checked={newsletter} onChange={e => setNewsletter(e.target.checked)}/>
                  <span>{t('Tenez-moi informé des nouveautés (newsletter, sans spam).','Keep me posted about updates (newsletter, no spam).')}</span>
                </label>
                <button className="btn btn-light btn-big" onClick={claim}><Icon name="bolt.fill" size={18}/>{t('Obtenir mon code','Get my code')}</button>
                <p className="mini">{t('Votre e-mail garantit un code par personne. Jamais partagé avec des tiers.','Your email ensures one code per person. Never shared with third parties.')}</p>
              </div>
            )}
            {state === 'loading' && (
              <button className="btn btn-light btn-big" disabled><span className="spinner"/>{t('Génération…','Generating…')}</button>
            )}
            {state === 'done' && (
              <div>
                <div style={{ fontSize:13, fontWeight:700, letterSpacing:.5, opacity:.85, marginBottom:10 }}>{t('VOTRE CODE','YOUR CODE')}</div>
                <div className="code">{code}</div>
                <div className="row2">
                  <a className="btn btn-light" href={redeemUrl} target="_blank" rel="noopener"><AppleLogo/>{t('Utiliser sur l\'App Store','Redeem on App Store')}</a>
                  <button className="btn" style={{ background:'rgba(255,255,255,.18)', color:'#fff' }} onClick={copy}>{copied ? t('Copié ✓','Copied ✓') : t('Copier','Copy')}</button>
                </div>
                <p className="mini">{t('Ouvrez le lien sur votre iPhone/iPad/Mac connecté à l\'App Store, ou saisissez le code dans App Store → votre photo → « Utiliser une carte cadeau ou un code ».','Open the link on your iPhone/iPad/Mac signed in to the App Store, or enter the code in App Store → your photo → “Redeem Gift Card or Code”.')}</p>
              </div>
            )}
            {state === 'sent' && (
              <div>
                <div style={{ fontSize:40, lineHeight:1 }}>📬</div>
                <div style={{ fontSize:20, fontWeight:800, margin:'8px 0 4px' }}>{t('Vérifiez votre boîte mail','Check your inbox')}</div>
                <p className="mini" style={{ opacity:.95 }}>{t('Votre code vient d\'être envoyé à votre adresse e-mail (pensez à regarder les spams). Ouvrez-le sur votre appareil Apple pour l\'utiliser.','Your code has just been sent to your email (check spam too). Open it on your Apple device to redeem.')}</p>
              </div>
            )}
            {state === 'ipblocked' && (
              <div>
                <div style={{ fontSize:18, fontWeight:700, marginBottom:6 }}>{t('Déjà réclamé','Already claimed')}</div>
                <p className="mini" style={{ opacity:.95 }}>{t('Un code a déjà été demandé depuis cet appareil ou ce réseau. Un seul par personne.','A code has already been requested from this device or network. One per person.')}</p>
                <a className="btn btn-light" style={{ marginTop:14 }} href={APP_STORE_URL} target="_blank" rel="noopener"><AppleLogo/>App Store</a>
              </div>
            )}
            {state === 'soldout' && (
              <div><div style={{ fontSize:18, fontWeight:700, marginBottom:6 }}>{t('Plus de codes','All codes claimed')}</div><p className="mini" style={{ opacity:.95 }}>{t('Tous les codes ont été distribués pour le moment. Vous pouvez quand même télécharger l\'app.','All free codes are gone for now. You can still download the app.')}</p><a className="btn btn-light" style={{ marginTop:14 }} href={APP_STORE_URL} target="_blank" rel="noopener"><AppleLogo/>App Store</a></div>
            )}
            {state === 'error' && (
              <div><button className="btn btn-light btn-big" onClick={claim}>{t('Réessayer','Try again')}</button><p className="mini">{t('Le générateur n\'est pas encore disponible — réessayez bientôt.','The generator isn\'t live yet — try again soon.')}</p></div>
            )}
          </div>

          <div className="steps">
            {[
              { n:1, h:t('Récupérez le code','Grab your code'), p:t('Un clic, un code unique rien que pour vous.','One click, one unique code just for you.') },
              { n:2, h:t('Ouvrez l\'App Store','Open the App Store'), p:t('Le lien ouvre directement l\'écran d\'échange.','The link opens the redeem screen directly.') },
              { n:3, h:t('Profitez d\'un mois','Enjoy a month'), p:t('Votre essai démarre, sans engagement.','Your trial starts, no commitment.') },
            ].map(s => (
              <div key={s.n} className="step"><div className="n">{s.n}</div><h5>{s.h}</h5><p>{s.p}</p></div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
};

const Footer = () => {
  const t = useT();
  return (
    <footer>
      <div className="wrap">
        <div className="foot">
          <a className="brand" href="#top"><img src="icon.png" alt="" style={{ width:26, height:26, borderRadius:7 }}/>Rclone GUI</a>
          <div className="nav-sp"/>
          <a href={APP_STORE_URL} target="_blank" rel="noopener">App Store</a>
          <a href={GITHUB_URL} target="_blank" rel="noopener">GitHub</a>
          <a href="privacy">{t('Confidentialité','Privacy')}</a>
          <a href="https://rclone.org" target="_blank" rel="noopener">rclone.org</a>
        </div>
        <p className="legal">{t('Rclone GUI est un client open-source (MPL-2.0) bâti sur rclone et SwiftUI. « rclone » est une marque de ses détenteurs respectifs ; cette application n\'est pas affiliée. Codes d\'essai limités, un par personne, dans la limite des stocks disponibles.','Rclone GUI is an open-source client (MPL-2.0) built on rclone and SwiftUI. “rclone” is a trademark of its respective owners; this app is not affiliated. Trial codes are limited, one per person, while supplies last.')}</p>
      </div>
    </footer>
  );
};

const App = () => {
  const [lang, setLang] = React.useState('en');
  return (
    <LangContext.Provider value={lang}>
      <Header lang={lang} setLang={setLang}/>
      <Hero/>
      <Gallery lang={lang}/>
      <Features/>
      <FreeMonth/>
      <Footer/>
    </LangContext.Provider>
  );
};

ReactDOM.createRoot(document.getElementById('root')).render(<App/>);
