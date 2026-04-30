import { minimatch } from "minimatch"
import { QuartzFilterPlugin } from "../types"

type Options = { patterns: string[] }

export const WhitelistPaths: QuartzFilterPlugin<Options> = (opts) => {
  const patterns = opts?.patterns ?? []
  return {
    name: "WhitelistPaths",
    shouldPublish(_ctx, [_tree, vfile]) {
      const slug = vfile.data.slug ?? ""
      return patterns.some((pattern: string) => minimatch(slug, pattern))
    },
  }
}
