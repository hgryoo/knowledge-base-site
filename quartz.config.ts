import { QuartzConfig } from "./quartz/cfg"
import * as Plugin from "./quartz/plugins"

/**
 * Quartz 4 Configuration
 *
 * See https://quartz.jzhao.xyz/configuration for more information.
 */

// Build modes:
//   default                - GitHub Pages: only the index page and the
//                            code-analysis category are published
//                            (WhitelistPaths filter applied below).
//   QUARTZ_LOCAL_FULL=1    - Local LAN deploy: every curated doc under
//                            knowledge/ is exposed. Used by
//                            scripts/serve-local.sh.
const isLocalFull = process.env.QUARTZ_LOCAL_FULL === "1"

const config: QuartzConfig = {
  configuration: {
    pageTitle: "hgryoo's Knowledge Base",
    pageTitleSuffix: "",
    enableSPA: true,
    enablePopovers: true,
    analytics: null,
    locale: "en-US",
    baseUrl: "hgryoo.github.io/knowledge-base-site",
    ignorePatterns: [
      "private",
      "templates",
      ".obsidian",
      "**/CLAUDE.md",
      "**/.omc/**",
      "**/.claude/**",
      // TODO: large textbook captures — raw C++/Java template syntax
      // (`<Map<LockObject<?>, ...>>`, etc.) confuses the markdown→HTML
      // pipeline and breaks ContentPage emit. Same root cause as the
      // 'attrs' processing error on database-system-concepts.md. Debug
      // separately or fence the offending blocks at the source.
      "**/database-system-concepts.md",
      "**/the-art-of-multiprocessor-programming.md",
      "**/systems-performance-gregg.md",
      "**/computer-systems-a-programmers-perspective.md",
    ],
    defaultDateType: "modified",
    theme: {
      fontOrigin: "googleFonts",
      cdnCaching: true,
      typography: {
        header: "Schibsted Grotesk",
        body: "Source Sans Pro",
        code: "IBM Plex Mono",
      },
      colors: {
        lightMode: {
          light: "#faf8f8",
          lightgray: "#e5e5e5",
          gray: "#b8b8b8",
          darkgray: "#4e4e4e",
          dark: "#2b2b2b",
          secondary: "#284b63",
          tertiary: "#84a59d",
          highlight: "rgba(143, 159, 169, 0.15)",
          textHighlight: "#fff23688",
        },
        darkMode: {
          light: "#161618",
          lightgray: "#393639",
          gray: "#646464",
          darkgray: "#d4d4d4",
          dark: "#ebebec",
          secondary: "#7b97aa",
          tertiary: "#84a59d",
          highlight: "rgba(143, 159, 169, 0.15)",
          textHighlight: "#b3aa0288",
        },
      },
    },
  },
  plugins: {
    transformers: [
      Plugin.FrontMatter(),
      Plugin.CreatedModifiedDate({
        priority: ["frontmatter", "git", "filesystem"],
      }),
      Plugin.SyntaxHighlighting({
        theme: {
          light: "github-light",
          dark: "github-dark",
        },
        keepBackground: false,
      }),
      Plugin.ObsidianFlavoredMarkdown({ enableInHtmlEmbed: false }),
      Plugin.GitHubFlavoredMarkdown(),
      Plugin.TableOfContents(),
      Plugin.CrawlLinks({ markdownLinkResolution: "shortest", prettyLinks: false }),
      Plugin.Description(),
      Plugin.Latex({ renderEngine: "katex" }),
    ],
    filters: [
      Plugin.RemoveDrafts(),
      ...(isLocalFull
        ? []
        : [
            Plugin.WhitelistPaths({
              patterns: ["index", "*/code-analysis/**"],
            }),
          ]),
    ],
    emitters: [
      Plugin.AliasRedirects(),
      Plugin.ComponentResources(),
      Plugin.ContentPage(),
      Plugin.FolderPage(),
      Plugin.TagPage(),
      Plugin.ContentIndex({
        enableSiteMap: true,
        enableRSS: true,
      }),
      Plugin.Assets(),
      Plugin.Static(),
      Plugin.Favicon(),
      Plugin.NotFoundPage(),
      // Comment out CustomOgImages to speed up build time
      Plugin.CustomOgImages(),
    ],
  },
}

export default config
