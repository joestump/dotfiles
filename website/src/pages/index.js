import React from 'react';
import Layout from '@theme/Layout';
import Link from '@docusaurus/Link';
import styles from './index.module.css';

const FEATURES = [
  {k: 'chezmoi', t: 'chezmoi', d: 'One source of truth. dot_zshrc, custom helpers, configs — applied byte-for-byte on any machine.'},
  {k: 'openbao', t: 'OpenBao + Vault Agent', d: 'Secrets never touch the repo. A launchd agent renders them from OpenBao on a schedule; the shell just sources them.'},
  {k: 'omz', t: 'Oh My Zsh', d: 'Curated plugins, a random cute prompt glyph, spaceship + Ghostty, helpers auto-loaded from $ZSH_CUSTOM.'},
  {k: 'pages', t: 'Garage Pages CI', d: 'BATS + shellcheck on every push; this very site builds and ships to Garage S3 from Gitea Actions.'},
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

export default function Home() {
  return (
    <Layout title="StumpCloud Dotfiles" description="chezmoi + Oh My Zsh + OpenBao — one command, any machine.">
      <header className={styles.hero}>
        <div className={styles.heroInner}>
          <p className={styles.kicker}>// STUMPCLOUD SYSTEMS</p>
          <h1 className={styles.title}>DOT<span className={styles.mag}>FILES</span></h1>
          <p className={styles.tagline}>
            chezmoi &middot; Oh My Zsh &middot; OpenBao &middot; Garage Pages.<br/>
            One command boots the <span className={styles.cyan}>mothership</span> or a throwaway <span className={styles.mag}>utility node</span>.
          </p>
          <div className={styles.cta}>
            <Link className={styles.btnPrimary} to="/docs/bootstrap/mothership">▶ Boot the Mothership</Link>
            <Link className={styles.btnGhost} to="/docs/overview">Read the docs</Link>
          </div>
          <Term />
        </div>
      </header>

      <main className={styles.grid}>
        {FEATURES.map((f) => (
          <Link key={f.k} className={styles.card} to="/docs/overview">
            <div className={styles.cardTag}>{f.k}</div>
            <h3 className={styles.cardTitle}>{f.t}</h3>
            <p className={styles.cardDesc}>{f.d}</p>
          </Link>
        ))}
      </main>
    </Layout>
  );
}
