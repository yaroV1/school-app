#!/usr/bin/env ruby
# frozen_string_literal: true

# PreToolUse(Bash). Enforces the absolutes in docs/agent-rules.md § Git. Permission rules are
# prefix-matched, so `git push origin main --force` walks past a `Bash(git push --force:*)` deny.
# This does not.
#
# Quoted text is stripped before anything is matched, and every rule is keyed on the git subcommand
# and its flags — never on a path or a commit message. Matching the raw command string instead blocks
# `git add config/locales/uk.yml` and `git commit -m "...clean..."`.
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

# `-nm` means `-n -m`, so a short flag has to be looked for inside a cluster too.
def short?(flags, char)
  flags.any? { |flag| /\A-[a-zA-Z]+\z/.match?(flag) && flag.include?(char) }
end

# git's own options that take a separate value, so the value is not read as the subcommand.
VALUED = %w[-C -c --git-dir --work-tree --namespace --exec-path].freeze
READ_ONLY_CONFIG = %w[--get --get-all --get-regexp --list -l].freeze

command.gsub(/'[^']*'/, " ").gsub(/"(?:\\.|[^"\\])*"/, " ").split(/;|&&|\|\||\n/).each do |segment|
  tokens = segment.split
  start = tokens.index { |token| token == "git" || token.end_with?("/git") }
  next unless start

  rest = tokens[(start + 1)..] || []
  sub = nil
  args = []
  skip = false
  rest.each_with_index do |token, i|
    if skip
      skip = false
    elsif token.start_with?("-")
      skip = VALUED.include?(token)
    else
      sub = token
      args = rest[(i + 1)..] || []
      break
    end
  end
  next unless sub

  flags = args.select { |token| token.start_with?("-") }

  case sub
  when "stash", "clean", "restore"
    block("git #{sub} discards uncommitted work")
  when "checkout"
    block("git checkout discards uncommitted work") if args.include?("--") || args.include?(".")
  when "push"
    block("force-push") if flags.any? { |flag| flag.start_with?("--force") } || short?(flags, "f")
    block("push --no-verify") if flags.include?("--no-verify")
  when "commit"
    block("commit --no-verify") if flags.include?("--no-verify") || short?(flags, "n")
    block("commit --amend") if flags.include?("--amend")
  when "config"
    block("git config change") if (flags & READ_ONLY_CONFIG).empty?
  when "add"
    block("git add -A / --all / .") if flags.include?("--all") || short?(flags, "A") || args.include?(".")
  when "reset"
    block("git reset --hard") if flags.include?("--hard")
  end
end

exit 0
