import React from 'react';
import Layout from '@theme/Layout';
import Link from '@docusaurus/Link';
import styles from './index.module.css';

const FEATURES = [
  {k: 'chezmoi', t: 'chezmoi', to: '/docs/workflow',
   d: 'Two checkouts, two roles: a production clone pinned to upstream main that renders $HOME, and a workbench you actually edit.'},
  {k: 'openbao', t: 'OpenBao + Vault Agent', to: '/docs/secrets',
   d: 'Secrets never touch the repo. A supervised agent renders env files, AWS credentials, a .netrc and SSH keys from OpenBao on a schedule.'},
  {k: 'harness', t: 'harness', to: '/docs/claude/harness',
   d: 'systemctl for your agents. Supervises Crush and Claude Code sessions, runs their cron schedules, and hands you the whole cockpit over SSH.'},
  {k: 'agents', t: 'One set of rules', to: '/docs/claude/agents',
   d: 'Claude Code, Claude Desktop and Crush compose their rules from the same partials — and every identity value is derived, never stored.'},
  {k: 'omz', t: 'Oh My Zsh', to: '/docs/terminal',
   d: 'Curated plugins, a random cute prompt glyph, spaceship + Ghostty, helpers auto-loaded from $ZSH_CUSTOM.'},
  {k: 'czu', t: 'czu', to: '/docs/commands',
   d: 'One command syncs, applies, re-renders secrets and reloads the shell — and runs itself every 6h, silent unless something breaks.'},
  {k: 'packages', t: 'Declarative tooling', to: '/docs/packages',
   d: 'A Brewfile, an apt list and a Go tools list. Add a line, merge, done — plus three things built from source on apply.'},
  {k: 'services', t: 'Services & schedules', to: '/docs/services',
   d: 'Daemons and timers, systemd --user on Linux and launchd on macOS, from one source — including a detector for the secret outage you would never otherwise notice.'},
  {k: 'pages', t: 'Garage Pages CI', to: '/docs/architecture',
   d: 'BATS, shellcheck and gitleaks on every push; this very site builds once and ships to both Garage S3 and GitHub Pages.'},
];

function Term() {
  return (
    <div className={styles.term}>
      <div className={styles.termBar}>
        <span className={styles.dot} style={{background:'#ff5f56'}} />
        <span className={styles.dot} style={{background:'#ffbd2e'}} />
        <span className={styles.dot} style={{background:'#27c93f'}} />
        <span className={styles.termTitle}>joestump@mothership — zsh</span>
      </div>
      <pre className={styles.termBody}>
<span className={styles.muted}>{'# boot any machine in one line:'}</span>{'\n'}
<span className={styles.prompt}>$ </span>sh -c "$(curl -fsLS get.chezmoi.io)" -- \{'\n'}
{'      '}init --apply gitea.stump.rocks/joestump/dotfiles{'\n'}
<span className={styles.ok}>{'==> prerequisites ready'}</span>{'\n'}
<span className={styles.ok}>{'==> packages installed'}</span>{'\n'}
<span className={styles.ok}>{'==> secrets rendered'}</span>{'  '}<span className={styles.cursor}>▋</span>
      </pre>
    </div>
  );
}

const SHOTS = [
  {src: require('@site/static/img/screenshots/motd.png').default,  alt: 'StumpCloud login banner (MOTD)',
   cap: 'The StumpCloud MOTD — dynamic host facts on every new shell, with the vault lock in the status dock.'},
  {src: require('@site/static/img/screenshots/czu.png').default,   alt: 'czu update output',
   cap: 'czu — one command syncs, applies, and re-renders secrets, with clean per-phase checks.'},
  {src: require('@site/static/img/screenshots/menus.png').default, alt: 'the dot menu and status dashboard',
   cap: 'The dot action hub and status health panel — gum-powered TUI helpers.'},
];

function Carousel() {
  const [i, setI] = React.useState(0);
  const n = SHOTS.length;
  const go = (d) => setI((x) => (x + d + n) % n);
  React.useEffect(() => {
    const t = setInterval(() => setI((x) => (x + 1) % n), 6000);
    return () => clearInterval(t);
  }, [n]);
  return (
    <div className={styles.carousel}>
      <div className={styles.carFrame}>
        <div className={styles.termBar}>
          <span className={styles.dot} style={{background:'#ff5f56'}} />
          <span className={styles.dot} style={{background:'#ffbd2e'}} />
          <span className={styles.dot} style={{background:'#27c93f'}} />
        </div>
        <div className={styles.carViewport}>
          {SHOTS.map((s, idx) => (
            <img key={idx} src={s.src} alt={s.alt} className={styles.carImg}
                 style={{opacity: idx === i ? 1 : 0}} />
          ))}
          <button className={`${styles.carNav} ${styles.carPrev}`} onClick={() => go(-1)} aria-label="Previous">&#8249;</button>
          <button className={`${styles.carNav} ${styles.carNext}`} onClick={() => go(1)} aria-label="Next">&#8250;</button>
        </div>
      </div>
      <p className={styles.carCap}>{SHOTS[i].cap}</p>
      <div className={styles.carDots}>
        {SHOTS.map((_, idx) => (
          <button key={idx} aria-label={`Slide ${idx + 1}`}
                  className={idx === i ? styles.carDotOn : styles.carDot} onClick={() => setI(idx)} />
        ))}
      </div>
    </div>
  );
}

export default function Home() {
  return (
    <Layout title="StumpCloud Dotfiles" description="chezmoi + Oh My Zsh + OpenBao — one command, any machine.">
      <header className={styles.hero}>
        <div className={styles.heroInner}>
          <p className={styles.kicker}>// STUMPCLOUD SYSTEMS</p>
          <h1 className={styles.title}>DOT<span className={styles.mag}>FILES</span></h1>
          <p className={styles.tagline}>
            chezmoi &middot; Oh My Zsh &middot; OpenBao &middot; Garage Pages.<br/>
            One command installs the <span className={styles.cyan}>hub</span> (macOS) or a throwaway <span className={styles.mag}>Linux spoke</span>.
          </p>
          <div className={styles.cta}>
            <Link className={styles.btnPrimary} to="/docs/install/mothership">▶ Install</Link>
            <Link className={styles.btnGhost} to="/docs/overview">Read the docs</Link>
          </div>
          <Term />
        </div>
      </header>

      <main className={styles.grid}>
        {FEATURES.map((f) => (
          <Link key={f.k} className={styles.card} to={f.to}>
            <div className={styles.cardTag}>{f.k}</div>
            <h3 className={styles.cardTitle}>{f.t}</h3>
            <p className={styles.cardDesc}>{f.d}</p>
          </Link>
        ))}
      </main>

      <section className={styles.gallery}>
        <p className={styles.kicker}>// SEE IT IN ACTION</p>
        <Carousel />
      </section>
    </Layout>
  );
}
