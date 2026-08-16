#!/usr/bin/env ruby
# frozen_string_literal: true

# PreToolUse(Bash). Enforces the absolutes in docs/agent-rules.md § Git by inspecting the whole
# command string. Permission rules are prefix-matched, so `git push origin main --force`
# walks past a `Bash(git push --force:*)` deny. This does not.
#
# Exit 2 blocks the tool call and shows stderr to the agent. Fails open only if stdin
# is not parseable JSON.

require "json"

command = begin
  JSON.parse($stdin.read.force_encoding("UTF-8")).dig("tool_input", "command").to_s
rescue StandardError
  ""
end

def block(reason)
  warn "Blocked by .claude/hooks/git-guard.rb: #{reason}. See docs/agent-rules.md § Git."
  exit 2
end

FORCE  = /(--force\b|--force-with-lease\b|(?<![\w-])-f\b)/
NOVER  = /(--no-verify\b|(?<![\w-])-n\b)/
ADDALL = /(--all\b|(?<![\w-])-A\b|\sadd\s+\.(\s|$))/

command.split(/;|&&|\|\||\n/).each do |segment|
  next unless /(^|\s|\/)git\s/.match?(segment)

  block("force-push")            if /\bpush\b/.match?(segment) && FORCE.match?(segment)
  block("push --no-verify")      if /\bpush\b/.match?(segment) && /--no-verify\b/.match?(segment)
  block("commit --no-verify")    if /\bcommit\b/.match?(segment) && NOVER.match?(segment)
  block("commit --amend")        if /\bcommit\b/.match?(segment) && /--amend\b/.match?(segment)
  block("git config change")     if /\bconfig\b/.match?(segment) && !/--(get|list)\b/.match?(segment)
  block("git add -A / --all / .") if /\badd\b/.match?(segment) && ADDALL.match?(segment)
  block("discards uncommitted work") if /\b(stash|clean)\b/.match?(segment)
  block("git reset --hard")      if /\breset\b/.match?(segment) && /--hard\b/.match?(segment)
end

exit 0
