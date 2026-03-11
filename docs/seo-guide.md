# WhisPaste SEO & ASO Guide

> Comprehensive, actionable playbook for maximising the organic visibility of WhisPaste across website search, GitHub, Microsoft Store, AI-powered search engines, and distribution channels.

---

## Table of Contents

1. [Keyword Research & Strategy](#1-keyword-research--strategy)
2. [Website SEO (whispaste.de)](#2-website-seo-whispastede)
3. [GitHub SEO](#3-github-seo)
4. [Microsoft Store ASO](#4-microsoft-store-aso)
5. [AI Search Optimization](#5-ai-search-optimization)
6. [Distribution & Visibility](#6-distribution--visibility)
7. [Backlink Strategy](#7-backlink-strategy)
8. [Monitoring & Analytics](#8-monitoring--analytics)

---

## 1. Keyword Research & Strategy

Before optimising any channel, nail down the keywords people actually search for.

### 1.1 Primary Keywords

These are the high-volume, high-intent terms to target across all channels.

| Keyword | Monthly Search Volume (est.) | Intent | Priority |
|---|---|---|---|
| speech to text windows | 2,000–5,000 | Transactional | 🔴 High |
| voice typing software | 1,000–3,000 | Transactional | 🔴 High |
| dictation software windows | 1,000–3,000 | Transactional | 🔴 High |
| whisper transcription | 500–1,500 | Informational/Transactional | 🔴 High |
| speech to text app | 3,000–8,000 | Transactional | 🔴 High |
| free dictation software | 1,000–2,500 | Transactional | 🔴 High |
| voice to text windows | 1,000–3,000 | Transactional | 🔴 High |
| open source speech to text | 500–1,500 | Transactional | 🟡 Medium |
| whisper api app | 200–800 | Transactional | 🟡 Medium |
| offline speech to text | 500–1,500 | Transactional | 🟡 Medium |

### 1.2 Long-Tail Keywords

Lower volume but higher conversion — target these in blog posts, FAQ sections, and landing page copy.

| Long-Tail Keyword | Content Format |
|---|---|
| best free speech to text software for windows | Blog post / comparison |
| how to use openai whisper for dictation | Tutorial blog post |
| whisper speech to text desktop app | Landing page |
| voice typing software that works in any app | Landing page feature copy |
| offline transcription software windows free | Blog post |
| speech to text paste into any field | Landing page / feature copy |
| dictation software for developers | Blog post |
| windows voice typing alternative | Blog post / comparison |
| whisper.cpp desktop gui | Landing page |
| system tray speech to text tool | Feature description |
| dictation app that pastes anywhere | Landing page headline variant |
| free alternative to dragon naturally speaking | Comparison blog post |
| local speech recognition no cloud | Blog post |
| voice note to text converter windows | Blog post |
| smart mode transcription formatting | Feature page |

### 1.3 Branded Keywords

Ensure you own search results for these:

- `whispaste`
- `whispaste download`
- `whispaste app`
- `whispaste windows`
- `whispaste github`

### 1.4 Competitor Keywords

Use these in comparison content (blog posts, not landing page):

- `dragon naturally speaking alternative free`
- `windows speech recognition alternative`
- `otter.ai desktop alternative`
- `whisper desktop app alternative`
- `voice typing without google docs`

---

## 2. Website SEO (whispaste.de)

### 2.1 On-Page SEO Checklist

Work through every item. Each one moves the needle.

#### Title Tags

- [ ] Homepage: `WhisPaste — Free Speech-to-Text App for Windows | Paste Anywhere`
- [ ] Keep titles under 60 characters (Google truncates after that)
- [ ] Include primary keyword + brand name
- [ ] Every page needs a unique `<title>` tag

#### Meta Descriptions

- [ ] Homepage: `WhisPaste turns your voice into text and pastes it into any app. Free, open-source, powered by OpenAI Whisper. Works online and offline. Download for Windows.`
- [ ] Keep descriptions between 150–160 characters
- [ ] Include a call-to-action ("Download free", "Try now")
- [ ] Include the primary keyword naturally

#### Heading Structure

- [ ] One `<h1>` per page — must contain the primary keyword
- [ ] Use `<h2>` for major sections, `<h3>` for subsections
- [ ] Don't skip heading levels (e.g. `<h1>` → `<h3>`)
- [ ] Homepage `<h1>` example: `Free Speech-to-Text for Windows — Paste Anywhere`

#### Open Graph Tags

```html
<meta property="og:title" content="WhisPaste — Free Speech-to-Text for Windows" />
<meta property="og:description" content="Record, transcribe, paste. WhisPaste turns your voice into text in any app. Free & open-source." />
<meta property="og:image" content="https://whispaste.de/og-image.png" />
<meta property="og:image:width" content="1200" />
<meta property="og:image:height" content="630" />
<meta property="og:url" content="https://whispaste.de/" />
<meta property="og:type" content="website" />
<meta property="og:site_name" content="WhisPaste" />
```

- [ ] Create a dedicated OG image (1200×630 px) with the app logo, tagline, and a screenshot
- [ ] Add `og:locale` tag: `<meta property="og:locale" content="en_US" />`

#### Twitter/X Card Tags

```html
<meta name="twitter:card" content="summary_large_image" />
<meta name="twitter:title" content="WhisPaste — Free Speech-to-Text for Windows" />
<meta name="twitter:description" content="Record, transcribe, paste. Free & open-source." />
<meta name="twitter:image" content="https://whispaste.de/og-image.png" />
```

#### Structured Data (Schema.org)

The site already has `SoftwareApplication` schema. Make sure it includes all of these fields:

```json
{
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  "name": "WhisPaste",
  "applicationCategory": "UtilitiesApplication",
  "operatingSystem": "Windows 10, Windows 11",
  "description": "Free, open-source speech-to-text app for Windows. Records your voice, transcribes via OpenAI Whisper or local models, and pastes the text into any input field.",
  "url": "https://whispaste.de",
  "downloadUrl": "https://github.com/whispaste/whispaste/releases/latest",
  "softwareVersion": "1.x.x",
  "author": {
    "@type": "Organization",
    "name": "WhisPaste",
    "url": "https://whispaste.de"
  },
  "offers": {
    "@type": "Offer",
    "price": "0",
    "priceCurrency": "USD"
  },
  "screenshot": "https://whispaste.de/screenshot.png",
  "featureList": [
    "Speech to text via OpenAI Whisper API",
    "Offline transcription with local models",
    "Paste text into any application",
    "Global hotkey activation",
    "System tray integration",
    "Smart mode with AI formatting",
    "Transcription history with search",
    "Multi-language support"
  ],
  "license": "https://opensource.org/licenses/MIT"
}
```

- [ ] Validate with [Google Rich Results Test](https://search.google.com/test/rich-results)
- [ ] Validate with [Schema.org Validator](https://validator.schema.org/)
- [ ] Keep `softwareVersion` in sync with actual releases

### 2.2 Technical SEO

#### Sitemap

- [ ] Generate `sitemap.xml` automatically (Astro has `@astrojs/sitemap` integration)
- [ ] Submit sitemap to Google Search Console and Bing Webmaster Tools
- [ ] Include all public pages, blog posts, and the changelog
- [ ] Set `<lastmod>` dates to actual content update dates

```
# Install Astro sitemap integration
npx astro add sitemap
```

In `astro.config.mjs`:
```js
import sitemap from '@astrojs/sitemap';

export default defineConfig({
  site: 'https://whispaste.de',
  integrations: [sitemap()],
});
```

#### robots.txt

```
User-agent: *
Allow: /

Sitemap: https://whispaste.de/sitemap-index.xml
```

- [ ] Don't block CSS/JS files (Google needs them for rendering)
- [ ] Block only admin/internal paths if any exist

#### Page Speed & Core Web Vitals

- [ ] Run [PageSpeed Insights](https://pagespeed.web.developers.google.com/) — aim for 90+ on mobile
- [ ] Run [web.dev/measure](https://web.dev/measure/) for a full Lighthouse audit
- [ ] Optimise images: use WebP/AVIF format, set explicit `width` and `height` attributes
- [ ] Lazy-load below-the-fold images: `loading="lazy"`
- [ ] Preload critical fonts and hero images
- [ ] Minimise render-blocking CSS/JS (Astro handles this well with islands)
- [ ] Enable gzip/Brotli compression on the hosting provider
- [ ] Use a CDN (Cloudflare, Vercel Edge, Netlify CDN)

**Core Web Vitals targets:**

| Metric | Target | What it measures |
|---|---|---|
| LCP (Largest Contentful Paint) | < 2.5 s | Loading performance |
| INP (Interaction to Next Paint) | < 200 ms | Interactivity |
| CLS (Cumulative Layout Shift) | < 0.1 | Visual stability |

#### Other Technical Items

- [ ] HTTPS everywhere (automatic with most hosting providers)
- [ ] Canonical URLs on every page: `<link rel="canonical" href="https://whispaste.de/..." />`
- [ ] 404 page with navigation back to homepage and search
- [ ] `hreflang` tags if you add a German version: `<link rel="alternate" hreflang="de" href="https://whispaste.de/de/" />`
- [ ] Mobile-responsive design (test at 320px, 375px, 768px, 1024px, 1440px)
- [ ] Semantic HTML (`<main>`, `<article>`, `<section>`, `<nav>`, `<footer>`)

### 2.3 Content Strategy

#### Landing Page Keyword Optimisation

The homepage should naturally include these terms in its copy:

- "speech to text" (in `<h1>` and first paragraph)
- "voice typing" (in a feature section)
- "dictation software" (in a comparison/positioning section)
- "whisper transcription" (in the how-it-works section)
- "paste anywhere" / "paste into any app" (unique selling proposition)
- "free" and "open-source" (in the hero section)
- "Windows" (in the hero and download section)
- "offline" (in a feature section, if applicable)

Don't keyword-stuff — write naturally and weave terms into compelling copy.

#### Blog Post Ideas

Create a `/blog` section on the website. Each post targets one long-tail keyword cluster.

| # | Blog Post Title | Target Keyword | Priority |
|---|---|---|---|
| 1 | How to Use OpenAI Whisper for Desktop Dictation | whisper dictation desktop | 🔴 High |
| 2 | 5 Best Free Speech-to-Text Apps for Windows in 2025 | free speech to text windows | 🔴 High |
| 3 | WhisPaste vs. Windows Voice Typing: What's the Difference? | windows voice typing alternative | 🔴 High |
| 4 | How to Transcribe Speech Offline on Windows (No Internet) | offline speech to text windows | 🟡 Medium |
| 5 | Why Developers Need a Desktop Dictation Tool | dictation software for developers | 🟡 Medium |
| 6 | Setting Up WhisPaste with a Local Whisper Model | whisper.cpp local model setup | 🟡 Medium |
| 7 | Dragon NaturallySpeaking vs. Free Alternatives | dragon alternative free | 🟡 Medium |
| 8 | Voice Typing in Any App: A Complete Guide | voice typing any app | 🟡 Medium |
| 9 | How to Speed Up Writing with Voice-to-Text | speed up writing voice | 🟢 Low |
| 10 | The Open-Source Speech-to-Text Stack Explained | open source speech to text | 🟢 Low |

**Blog post template:**
1. **Hook** — address the reader's pain point
2. **Solution** — introduce the concept
3. **How-to / comparison** — practical, detailed content
4. **WhisPaste mention** — natural product placement (not a hard sell)
5. **CTA** — download link with UTM parameters
6. Aim for 1,000–2,000 words per post
7. Include screenshots, GIFs, or video embeds

#### Internal Linking Strategy

- [ ] Every blog post links to the homepage download section
- [ ] Every blog post links to 1–2 other blog posts (topical clusters)
- [ ] Homepage links to top 3 blog posts (in a "Learn More" section)
- [ ] Feature sections link to relevant blog posts for deeper dives
- [ ] Use descriptive anchor text (not "click here" — use "learn how to set up offline transcription")

#### Image Alt Text

- [ ] Every image has descriptive `alt` text
- [ ] Include keywords naturally: `alt="WhisPaste settings window showing API key configuration"`
- [ ] Screenshots: describe what's shown, not just "screenshot"
- [ ] Icons/decorative images: use empty `alt=""` (don't describe decorative elements)
- [ ] File names should be descriptive too: `whispaste-transcription-history.webp` not `img001.webp`

---

## 3. GitHub SEO

GitHub repos rank well in Google. Optimise the repository for both GitHub search and Google.

### 3.1 Repository Metadata

#### Description (one-liner)

```
Free, open-source speech-to-text app for Windows. Record → Transcribe (Whisper) → Paste anywhere.
```

- [ ] Under 350 characters
- [ ] Include "speech-to-text", "Windows", "open-source", "Whisper"
- [ ] Describe the value proposition, not just the tech

#### Topics (Tags)

Add these topics to the repository (Settings → Topics):

```
speech-to-text
voice-typing
dictation
whisper
openai-whisper
transcription
windows-app
desktop-app
golang
open-source
productivity
accessibility
voice-recognition
speech-recognition
whisper-cpp
text-to-speech
system-tray
webview2
```

- [ ] Use 15–20 topics (GitHub allows up to 20)
- [ ] Include both technical terms (`golang`, `webview2`) and user-facing terms (`dictation`, `voice-typing`)
- [ ] Include the brand name: `whispaste`

#### Website URL

- [ ] Set the repository website to `https://whispaste.de`

### 3.2 README Optimisation

The README is your GitHub landing page. Structure it for humans AND search engines.

**Optimal README structure for SEO:**

```markdown
# WhisPaste

> Free, open-source speech-to-text app for Windows — record, transcribe, paste anywhere.

[Badges: build status, license, downloads, version, Microsoft Store link]

[Hero screenshot or GIF]

## Features
- List the key features with short descriptions

## Installation
- Microsoft Store link
- GitHub Releases (setup installer, portable)
- Winget / Scoop / Chocolatey commands

## Quick Start
- How to get up and running in 60 seconds

## How It Works
- Brief technical overview

## Configuration
- Key settings and options

## Contributing
- How to contribute

## License
```

**README SEO checklist:**

- [ ] First sentence contains "speech-to-text", "Windows", and "free"
- [ ] Include a hero GIF/screenshot (visual repos get more stars)
- [ ] Use descriptive headings (not just "Usage" — say "How to Use WhisPaste")
- [ ] Include installation commands for every distribution channel
- [ ] Add badges: ![Downloads](shields.io), ![License](shields.io), etc.
- [ ] Link to the website prominently
- [ ] Include a "Star this repo" call-to-action (subtle, at the bottom)

### 3.3 Releases

Each GitHub Release is an indexable page. Optimise release descriptions.

**Release description template:**

```markdown
## WhisPaste vX.Y.Z

### What's New
- Feature 1: [descriptive sentence with keywords]
- Feature 2: [descriptive sentence with keywords]

### Bug Fixes
- Fix 1

### Downloads
- **Setup Installer**: `WhisPaste-Setup-vX.Y.Z.exe`
- **Portable**: `WhisPaste-Portable-vX.Y.Z.zip`
- **Microsoft Store**: [link]

### Checksums (SHA256)
[checksums]

---
WhisPaste is a free, open-source speech-to-text app for Windows.
Learn more at https://whispaste.de
```

- [ ] Always include the product description footer (it's crawled)
- [ ] Use descriptive feature names, not just "added X" — say "Added offline transcription with local Whisper models"

### 3.4 GitHub Discussions

- [ ] Enable GitHub Discussions on the repo
- [ ] Create categories: Announcements, Q&A, Feature Requests, Show & Tell
- [ ] Pin a welcome post with links to docs, website, and getting started
- [ ] Engage with questions — active discussions improve repo visibility

### 3.5 Awesome-List Submissions

Submit WhisPaste to relevant awesome lists. Each one is a high-quality backlink.

| Awesome List | Link | Category |
|---|---|---|
| awesome-whisper | Search on GitHub | Speech-to-text tools |
| awesome-speech-recognition | Search on GitHub | Desktop apps |
| awesome-productivity | Search on GitHub | Dictation / writing tools |
| awesome-golang | Search on GitHub | Desktop applications |
| awesome-windows | Search on GitHub | Utilities / productivity |
| awesome-open-source | Search on GitHub | Developer tools |
| awesome-accessibility | Search on GitHub | Assistive technology |

**How to submit:**
1. Fork the awesome list
2. Add WhisPaste in the appropriate section (alphabetical order)
3. Format: `- [WhisPaste](https://github.com/whispaste/whispaste) - Free, open-source speech-to-text app for Windows. Record, transcribe with Whisper, paste anywhere.`
4. Submit a PR with a clear description

---

## 4. Microsoft Store ASO

App Store Optimisation for the Microsoft Store follows similar principles to mobile ASO.

### 4.1 App Listing Optimisation

#### App Name

```
WhisPaste — Speech to Text & Voice Typing
```

- [ ] Keep the brand name first
- [ ] Add a keyword-rich subtitle after the dash
- [ ] Stay under 256 characters (Microsoft's limit)
- [ ] Don't use ALL CAPS

#### Short Description (first 252 characters)

```
Free speech-to-text app for Windows. Record your voice, transcribe with OpenAI Whisper or local models, and paste the text into any application. Works offline. Open-source.
```

- [ ] First 100 characters are the most important (shown in search results)
- [ ] Include the primary keywords: "speech-to-text", "voice", "transcribe", "Whisper", "free"
- [ ] Include "Windows" and "free" — top search filters

#### Full Description

Structure the full description with these keyword-rich sections:

```
WhisPaste — Free Speech-to-Text for Windows

Turn your voice into text and paste it anywhere. WhisPaste is a free, open-source
dictation and voice typing tool for Windows 10 and Windows 11.

HOW IT WORKS
1. Press a hotkey or click the system tray icon
2. Speak naturally — WhisPaste records your voice
3. Your speech is transcribed using OpenAI Whisper (online) or local models (offline)
4. The text is automatically pasted into the active application

KEY FEATURES
• Speech-to-text powered by OpenAI Whisper API
• Offline transcription with local Whisper models — no internet required
• Paste text into ANY application — browsers, editors, chat apps, email
• Global hotkey for hands-free activation
• Smart Mode: AI-powered formatting (punctuation, paragraphs, lists)
• Transcription history with full-text search
• Multi-language speech recognition
• Lightweight system tray app — stays out of your way
• 100% free and open-source (MIT License)

WHO IS IT FOR?
• Writers and content creators who want to draft faster
• Developers who prefer dictating code comments and documentation
• Professionals who need hands-free note-taking
• Anyone who types a lot and wants a faster alternative

PRIVACY
Your audio is processed via the OpenAI API (when using online mode) or entirely
on your device (when using offline mode). No data is stored on external servers
by WhisPaste. The app is open-source — inspect the code yourself.

REQUIREMENTS
• Windows 10 version 1809 or later / Windows 11
• OpenAI API key (for online mode) or local Whisper model (for offline mode)
• Microphone

FREE & OPEN SOURCE
WhisPaste is MIT-licensed and community-driven. Contribute, report bugs, or
suggest features on GitHub: https://github.com/whispaste/whispaste
```

- [ ] Use ALL CAPS for section headers (Microsoft Store renders them as bold)
- [ ] Include keywords naturally in every section
- [ ] Add "free" and "open-source" multiple times (high-value filter keywords)
- [ ] List specific use cases (helps with long-tail searches)

#### Search Keywords / Terms

Microsoft Store allows you to add search terms in Partner Center. Use these:

```
speech to text
voice typing
dictation
whisper
transcription
voice to text
speech recognition
voice recognition
dictation software
whisper ai
offline transcription
voice notes
speech transcription
text to speech
voice dictation
openai whisper
free dictation
paste anywhere
```

- [ ] Use all available keyword slots
- [ ] Don't repeat words already in the title
- [ ] Include misspellings people commonly make: `speach to text` (if allowed)
- [ ] Include both US and UK spellings where applicable

### 4.2 Screenshots & Visual Assets

| Asset | Specs | Tips |
|---|---|---|
| App icon | 300×300 px (+ sizes) | Clean, recognisable at small sizes |
| Hero image | 1920×1080 px | Show the app in action with a tagline overlay |
| Screenshots | 1366×768 px minimum | Annotate with feature callouts |

**Screenshot strategy (5–10 screenshots):**

1. **Hero shot**: App in action — recording overlay visible over a document
2. **System tray**: Show the tray icon and menu
3. **Settings UI**: Clean settings interface
4. **History**: Transcription history with search
5. **Smart Mode**: Before/after of AI formatting
6. **Offline mode**: Local model selection
7. **Hotkey config**: Customisation options
8. **Multi-language**: Language selection dropdown

**Screenshot best practices:**
- [ ] Add text overlays with feature descriptions (e.g. "Paste into any app")
- [ ] Use a consistent visual style (same background, font, colours)
- [ ] Show the app in realistic use scenarios (over VS Code, Word, Slack, etc.)
- [ ] First 2 screenshots matter most — they're shown in search results

### 4.3 Category Selection

- **Primary category**: Productivity
- **Secondary category**: Utilities & Tools

### 4.4 Review Solicitation

More reviews = better ranking. But don't be spammy.

- [ ] Add an in-app prompt after 5 successful transcriptions: "Enjoying WhisPaste? Rate us on the Microsoft Store!"
- [ ] Link directly to the Store review page (use `ms-windows-store://review/?ProductId=YOUR_PRODUCT_ID`)
- [ ] Only show the prompt once (store a `reviewPrompted` flag in config)
- [ ] Include a "Rate on Microsoft Store" link in the settings UI (low-key, always accessible)
- [ ] Respond to every Store review (positive and negative) — shows active development

---

## 5. AI Search Optimisation

AI-powered search engines (ChatGPT with browsing, Perplexity, Google AI Overviews, Bing Copilot) are becoming a significant traffic source. Here's how to appear in their responses.

### 5.1 Why This Matters

When someone asks ChatGPT or Perplexity "What's the best free speech-to-text app for Windows?", the AI synthesises answers from web content. You need your website and GitHub to be among its sources.

### 5.2 Structured Content That LLMs Parse Well

LLMs are good at extracting structured information. Make your content easy to parse.

#### Clear Product Definition Block

Add this to your homepage (visible or in structured data):

```html
<section itemscope itemtype="https://schema.org/SoftwareApplication">
  <h2>What is WhisPaste?</h2>
  <p>
    <span itemprop="name">WhisPaste</span> is a
    <span itemprop="applicationCategory">free, open-source speech-to-text application</span> for
    <span itemprop="operatingSystem">Windows 10 and Windows 11</span>.
    It records your voice, transcribes it using
    <strong>OpenAI Whisper</strong> (online) or <strong>local models</strong> (offline),
    and pastes the resulting text into any active application.
  </p>
</section>
```

#### Comparison Tables

LLMs love tables. Add a comparison table to your website:

```markdown
| Feature | WhisPaste | Windows Voice Typing | Dragon |
|---|---|---|---|
| Price | Free | Free (built-in) | $150+ |
| Open Source | ✅ Yes | ❌ No | ❌ No |
| Works in Any App | ✅ Yes | ⚠️ Limited | ✅ Yes |
| Offline Mode | ✅ Yes | ✅ Yes | ✅ Yes |
| AI Formatting | ✅ Smart Mode | ❌ No | ✅ Yes |
| Whisper Engine | ✅ Yes | ❌ No | ❌ No |
```

#### Feature Lists with Context

Instead of bare bullet points, provide context:

```
✅ Good for AI parsing:
"WhisPaste supports offline transcription using local Whisper models (whisper.cpp),
so no internet connection or API key is needed."

❌ Bad for AI parsing:
"Offline mode"
```

### 5.3 Schema.org Markup for AI

#### FAQ Schema

Add FAQ schema to your homepage or a dedicated FAQ page. LLMs heavily reference FAQ content.

```json
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "Is WhisPaste free?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Yes, WhisPaste is completely free and open-source under the MIT License. There are no hidden costs, subscriptions, or premium tiers."
      }
    },
    {
      "@type": "Question",
      "name": "Does WhisPaste work offline?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Yes. WhisPaste supports offline transcription using local Whisper models powered by whisper.cpp. No internet connection or API key is required for offline mode."
      }
    },
    {
      "@type": "Question",
      "name": "What speech recognition engine does WhisPaste use?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "WhisPaste uses OpenAI's Whisper model for speech recognition. You can either use the OpenAI Whisper API (online, requires API key) or run Whisper locally on your device using whisper.cpp (offline, no API key needed)."
      }
    },
    {
      "@type": "Question",
      "name": "Can WhisPaste paste text into any application?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Yes. WhisPaste pastes transcribed text into whatever application and input field is currently active — browsers, code editors, chat apps, email clients, word processors, and more."
      }
    },
    {
      "@type": "Question",
      "name": "What languages does WhisPaste support?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "WhisPaste supports all languages that OpenAI Whisper supports, which includes over 50 languages. The app interface is available in English and German."
      }
    }
  ]
}
```

#### HowTo Schema

```json
{
  "@context": "https://schema.org",
  "@type": "HowTo",
  "name": "How to Use WhisPaste for Speech-to-Text on Windows",
  "description": "Set up WhisPaste to transcribe your voice and paste text into any application on Windows.",
  "step": [
    {
      "@type": "HowToStep",
      "name": "Download and Install",
      "text": "Download WhisPaste from the Microsoft Store, GitHub Releases, or via winget. Install and launch the app."
    },
    {
      "@type": "HowToStep",
      "name": "Configure Your API Key or Local Model",
      "text": "Open WhisPaste settings from the system tray. Enter your OpenAI API key for online mode, or download a local Whisper model for offline mode."
    },
    {
      "@type": "HowToStep",
      "name": "Start Dictating",
      "text": "Press the global hotkey (default: Ctrl+Shift+Space) or click the system tray icon. Speak naturally. WhisPaste will transcribe your speech and paste the text into the active application."
    }
  ]
}
```

### 5.4 AI-Optimised Content Patterns

- [ ] **Answer questions directly** — start paragraphs with the answer, then elaborate
- [ ] **Use "What is X?" format** — LLMs often search for definitional content
- [ ] **Maintain a FAQ page** — highest-value content type for AI search
- [ ] **Include specific numbers** — "supports 50+ languages", "under 10 MB installer"
- [ ] **Compare to alternatives by name** — LLMs look for comparison content
- [ ] **Keep content fresh** — update the "last updated" date when you modify pages
- [ ] **Cite sources** — link to OpenAI's Whisper documentation, whisper.cpp repo, etc.

### 5.5 llms.txt File

Some AI crawlers look for a `llms.txt` file at the site root. Create one:

```
# WhisPaste

> Free, open-source speech-to-text app for Windows

WhisPaste records your voice, transcribes it using OpenAI Whisper (online or offline),
and pastes the text into any active application.

## Key Facts
- Price: Free (MIT License)
- Platform: Windows 10/11
- Speech engine: OpenAI Whisper API or local whisper.cpp models
- Works in: Any application with a text input field
- Languages: 50+ (Whisper-supported languages)

## Links
- Website: https://whispaste.de
- GitHub: https://github.com/whispaste/whispaste
- Microsoft Store: [link]
- Documentation: https://whispaste.de/docs
```

---

## 6. Distribution & Visibility

### 6.1 Software Directories

Submit WhisPaste to every relevant directory. Each listing is a backlink + discovery channel.

| Directory | URL | Priority | Notes |
|---|---|---|---|
| AlternativeTo | alternativeto.net | 🔴 High | List as alternative to Dragon, Windows Voice Typing, Otter.ai |
| Softpedia | softpedia.com | 🔴 High | Submit via their submission form |
| MajorGeeks | majorgeeks.com | 🟡 Medium | Email submission |
| SourceForge | sourceforge.net | 🟡 Medium | Mirror the releases |
| FossHub | fosshub.com | 🟡 Medium | Good for open-source software |
| Uptodown | uptodown.com | 🟡 Medium | Large audience |
| Softonic | softonic.com | 🟡 Medium | High traffic, submit via form |
| FileHippo | filehippo.com | 🟢 Low | Declining but still indexed |
| Chocolatey Community | community.chocolatey.org | 🔴 High | Developer audience |
| Winget | github.com/microsoft/winget-pkgs | 🔴 High | Direct install for developers |
| Scoop | scoop.sh | 🟡 Medium | Developer audience, portable apps |
| OSDN | osdn.net | 🟢 Low | Open-source software |
| Open Hub | openhub.net | 🟢 Low | Open-source analytics |

**Submission checklist for each directory:**

- [ ] Consistent product name: "WhisPaste"
- [ ] Same description everywhere (adapted for length limits)
- [ ] Link to official website (whispaste.de), not just GitHub
- [ ] Include screenshots
- [ ] Select correct categories: Productivity, Utilities, Speech Recognition
- [ ] Set license to MIT / Open Source
- [ ] Update listings when new versions are released

### 6.2 Package Managers

Getting into package managers is both a distribution channel and a credibility signal.

#### Winget

```yaml
# manifests/w/WhisPaste/WhisPaste/
PackageIdentifier: WhisPaste.WhisPaste
PackageVersion: X.Y.Z
PackageName: WhisPaste
Publisher: WhisPaste
License: MIT
ShortDescription: Free speech-to-text app for Windows
Description: Record your voice, transcribe with OpenAI Whisper, paste anywhere.
Tags:
  - speech-to-text
  - dictation
  - voice-typing
  - whisper
  - transcription
  - productivity
InstallerUrl: https://github.com/whispaste/whispaste/releases/download/vX.Y.Z/WhisPaste-Setup-vX.Y.Z.exe
InstallerType: exe
```

- [ ] Submit via PR to `microsoft/winget-pkgs`
- [ ] Set up GitHub Actions to auto-submit on new releases (use `vedantmgoyal2009/winget-releaser` action)

#### Chocolatey

- [ ] Create a Chocolatey package
- [ ] Submit to the community repository
- [ ] Auto-update with `au` (Chocolatey automatic updater)

#### Scoop

- [ ] Create a Scoop manifest for the portable version
- [ ] Submit to a Scoop bucket (extras or create your own)

### 6.3 Developer Communities

| Platform | Strategy | Timing |
|---|---|---|
| **Reddit** | Post to r/software, r/Windows10, r/Windows11, r/productivity, r/speechrecognition, r/openai, r/golang | On launch, major releases |
| **Hacker News** | "Show HN: WhisPaste — Open-source speech-to-text for Windows" | Once, on a big milestone |
| **Product Hunt** | Full launch with assets, description, maker story | Once, prepared launch |
| **Dev.to** | Write a "How I Built" article | Anytime |
| **Lobsters** | Submit if you have an invite | On launch |
| **Twitter/X** | Demo GIFs, feature announcements, engage with Whisper/AI community | Ongoing |
| **LinkedIn** | Professional angle: productivity, accessibility | On launch, major releases |
| **YouTube** | Demo video, tutorials | Evergreen content |

**Reddit posting tips:**
- Don't just self-promote — add value with the post (how it solves a problem, how it was built)
- Engage with every comment
- Follow each subreddit's self-promotion rules
- Wait at least a few weeks between posts to the same subreddit

**Hacker News tips:**
- Title format: `Show HN: WhisPaste – Free, open-source speech-to-text for Windows (Whisper)`
- Post on a Tuesday or Wednesday morning (US time)
- Be ready to answer questions for the first 2 hours
- Don't ask friends to upvote — that gets you flagged

**Product Hunt tips:**
- Prepare 5+ screenshots, a demo GIF, and a 60-second video
- Write a compelling maker story
- Launch on a Tuesday, Wednesday, or Thursday
- Engage with every comment on launch day

### 6.4 YouTube Video SEO

Create a demo video and optimise it for YouTube search.

**Video title:** `WhisPaste — Free Speech-to-Text App for Windows (Open Source, Whisper AI)`

**Video description:**
```
WhisPaste turns your voice into text and pastes it into any app on Windows.
Free, open-source, powered by OpenAI Whisper.

🔗 Download: https://whispaste.de
🔗 GitHub: https://github.com/whispaste/whispaste
🔗 Microsoft Store: [link]

In this video:
0:00 What is WhisPaste?
0:30 Installation
1:00 Setting up your API key
1:30 Your first transcription
2:00 Smart Mode (AI formatting)
2:30 Offline mode with local models
3:00 Transcription history

Tags: speech to text, voice typing, dictation software, whisper ai,
openai whisper, free dictation, windows app, open source
```

**YouTube SEO checklist:**
- [ ] Include target keywords in the title
- [ ] First 2 lines of description contain the primary keyword and a link
- [ ] Add timestamps (chapters)
- [ ] Add tags (YouTube still uses them for discovery)
- [ ] Create a custom thumbnail with text overlay
- [ ] Add end screens linking to the website
- [ ] Pin a comment with the download link

---

## 7. Backlink Strategy

Backlinks remain the #1 ranking factor. Focus on quality over quantity.

### 7.1 High-Value Backlink Sources

| Source Type | Examples | Effort | Value |
|---|---|---|---|
| Awesome lists | awesome-whisper, awesome-productivity | Low | 🔴 High |
| Software directories | AlternativeTo, Softpedia | Low | 🔴 High |
| Open-source directories | FOSS Post, It's FOSS, FOSSMint | Medium | 🔴 High |
| Guest blog posts | Dev.to, Medium, Hashnode | Medium | 🟡 Medium |
| Tutorial articles | "How to use Whisper for X" on tech blogs | Medium | 🟡 Medium |
| GitHub profile README | Your personal/org README | Low | 🟢 Low |
| Forum signatures | Relevant forums | Low | 🟢 Low |
| Press coverage | Tech blogs, productivity sites | High | 🔴 High |

### 7.2 Content Marketing Angles

Create content that others want to link to:

1. **"State of Open-Source Speech-to-Text in 2025"** — a comprehensive comparison post. Other sites will reference it.
2. **"How We Built a Desktop App with Go and WebView2"** — developer audience, gets shared on HN/Reddit.
3. **"Whisper vs. Other Speech Engines: A Benchmark"** — original research attracts links naturally.
4. **Infographic: "Voice Typing Saves X Hours Per Week"** — visual content gets embedded and linked.
5. **Open-source case study** — "From Side Project to Microsoft Store: Lessons Learned"

### 7.3 Partnership & Integration Opportunities

- **Text editors/IDEs**: Reach out to VS Code extension authors, Obsidian plugin developers — "WhisPaste works great alongside [their tool]"
- **Productivity bloggers**: Offer a demo/review copy and suggest a tutorial
- **Accessibility advocates**: WhisPaste helps people who can't type — reach out to accessibility communities
- **AI/Whisper community**: Engage with whisper.cpp, faster-whisper, and OpenAI community content
- **Podcast hosts**: Offer to be a guest on dev/productivity podcasts

### 7.4 Digital PR

- [ ] Write a launch press release (free distribution via openPR.com, PRLog.org)
- [ ] Submit to "apps of the week" columns (Lifehacker, MakeUseOf, How-To Geek)
- [ ] Submit to "open-source alternatives" articles (It's FOSS, FOSS Post)
- [ ] Pitch tech bloggers who cover productivity tools or Windows software

---

## 8. Monitoring & Analytics

### 8.1 Free Tools Setup

| Tool | What It Tracks | Priority |
|---|---|---|
| [Google Search Console](https://search.google.com/search-console) | Google rankings, clicks, impressions, indexing issues | 🔴 Must-have |
| [Bing Webmaster Tools](https://www.bing.com/webmasters) | Bing rankings (also feeds Yahoo, DuckDuckGo) | 🔴 Must-have |
| [Microsoft Partner Center](https://partner.microsoft.com) | Store installs, ratings, reviews, search terms | 🔴 Must-have |
| [Google Analytics 4](https://analytics.google.com) | Website traffic, user behaviour, conversions | 🔴 Must-have |
| [GitHub Insights](https://github.com/whispaste/whispaste/graphs/traffic) | Repo views, clones, referrers, popular content | 🟡 Free |
| [Plausible](https://plausible.io) or [Umami](https://umami.is) | Privacy-friendly website analytics (alternative to GA4) | 🟡 Optional |
| [Ahrefs Webmaster Tools](https://ahrefs.com/webmaster-tools) | Free backlink checker & site audit | 🟡 Free tier |
| [PageSpeed Insights](https://pagespeed.web.developers.google.com/) | Core Web Vitals, performance | 🟡 Free |

### 8.2 Setup Checklist

- [ ] **Google Search Console**: Verify ownership → Submit sitemap → Monitor weekly
- [ ] **Bing Webmaster Tools**: Verify → Import settings from GSC → Submit sitemap
- [ ] **Google Analytics 4**: Install tracking snippet → Set up conversion events (download clicks)
- [ ] **Microsoft Partner Center**: Check weekly for reviews, respond to all
- [ ] **GitHub Insights**: Check monthly for traffic trends and referrer sources

### 8.3 Key Performance Indicators (KPIs)

Track these metrics monthly and quarterly.

#### Website KPIs

| KPI | Target (3 months) | Target (12 months) | How to Measure |
|---|---|---|---|
| Organic search impressions | 5,000/month | 50,000/month | Google Search Console |
| Organic clicks | 200/month | 5,000/month | Google Search Console |
| Average position for primary keywords | Top 30 | Top 10 | Google Search Console |
| Website sessions | 500/month | 10,000/month | GA4 |
| Download button clicks | 50/month | 1,000/month | GA4 events |
| Core Web Vitals pass rate | 100% | 100% | PageSpeed Insights |
| Referring domains (backlinks) | 10 | 50+ | Ahrefs Webmaster Tools |

#### GitHub KPIs

| KPI | Target (3 months) | Target (12 months) | How to Measure |
|---|---|---|---|
| Stars | 50 | 500+ | GitHub Insights |
| Unique cloners | 20/week | 100/week | GitHub Traffic |
| Unique visitors | 100/week | 500/week | GitHub Traffic |
| Forks | 5 | 50+ | GitHub |
| Release downloads | 100 total | 2,000+ total | GitHub Releases |

#### Microsoft Store KPIs

| KPI | Target (3 months) | Target (12 months) | How to Measure |
|---|---|---|---|
| Store page views | 200/month | 2,000/month | Partner Center |
| Installs | 50/month | 500/month | Partner Center |
| Average rating | 4.0+ | 4.5+ | Partner Center |
| Number of reviews | 5 | 30+ | Partner Center |
| Search term rankings | Top 20 for "speech to text" | Top 10 | Partner Center |

### 8.4 Monthly Review Routine

Set a monthly calendar reminder to:

1. **Google Search Console** (15 min)
   - Check for indexing errors → fix immediately
   - Review top queries → identify new keyword opportunities
   - Check click-through rates → improve titles/descriptions for low-CTR pages

2. **Bing Webmaster Tools** (5 min)
   - Check for crawl errors
   - Review keyword performance

3. **Website Analytics** (10 min)
   - Top landing pages → double down on what works
   - Traffic sources → identify new referrers
   - Download click conversion rate → optimise the download CTA

4. **GitHub** (5 min)
   - Traffic sources → see where visitors come from
   - Popular content → understand what people look at
   - Stars trend → gauge momentum

5. **Microsoft Store** (10 min)
   - New reviews → respond to all
   - Search terms → adjust keywords if needed
   - Install trend → correlate with marketing efforts

6. **Backlinks** (10 min)
   - New referring domains in Ahrefs → check for unexpected links
   - Lost backlinks → reach out if a valuable link was removed

---

## Quick-Start Priority List

If you can only do 10 things, do these first:

| # | Action | Impact | Effort |
|---|---|---|---|
| 1 | Set up Google Search Console + submit sitemap | 🔴 High | 15 min |
| 2 | Optimise homepage `<title>`, `<meta description>`, `<h1>` | 🔴 High | 30 min |
| 3 | Add FAQ schema to the website | 🔴 High | 1 hour |
| 4 | Add 15–20 topics to the GitHub repo | 🔴 High | 5 min |
| 5 | Submit to AlternativeTo | 🔴 High | 15 min |
| 6 | Optimise Microsoft Store listing (title + description + keywords) | 🔴 High | 1 hour |
| 7 | Create `llms.txt` at the site root | 🟡 Medium | 15 min |
| 8 | Submit to winget-pkgs | 🟡 Medium | 1 hour |
| 9 | Write first blog post (target: "free speech to text windows") | 🟡 Medium | 3 hours |
| 10 | Post "Show HN" on Hacker News | 🟡 Medium | 30 min |

---

*Last updated: 2025. Review and update this guide quarterly.*
