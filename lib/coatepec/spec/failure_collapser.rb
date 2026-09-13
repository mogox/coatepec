# frozen_string_literal: true

module Coatepec
  module Spec
    # Collapses failure blocks that repeat one error verbatim (a broken layout erroring every controller
    # test, say) into the first block plus a roll-up line naming the other tests. Unrecognised text is kept.
    module FailureCollapser
      MINITEST_START = /\A(?:Error|Failure):\z/
      MINITEST_ID = /\A(\S+#\S+?)(?: \[[^\]]*\])?:\z/
      MINITEST_END = /\A\S.*\brails test \S+:\d+\z/
      RSPEC_START = /\A  \d+\) (.+)\z/
      RSPEC_END = /\A(?:  \d+\) |Finished in |Failed examples:)/
      # Backtrace frames and RSpec's "Failure/Error: <source line>" differ per test; the error text is what must match.
      IGNORED = %r{\A\s+(?:# )?\S+:\d+(?::in .*)?\z|\A\s+Failure/Error: }

      module_function

      def call(text)
        lines = text.lines
        blocks = minitest_blocks(lines)
        blocks = rspec_blocks(lines) if blocks.empty?
        return text if blocks.size < 2

        rewrite(lines, blocks)
      end

      # A block runs from the Error:/Failure: line through Rails' "bin/rails test path:LINE" rerun line.
      def minitest_blocks(lines)
        blocks = []
        i = 0
        while i < lines.size
          id, stop = minitest_block_end(lines, i)
          blocks << block(i, stop, id, lines[(i + 2)...stop]) if stop
          i = (stop || i) + 1
        end
        blocks
      end

      def minitest_block_end(lines, index)
        id = lines[index].chomp.match?(MINITEST_START) && lines[index + 1]&.chomp&.[](MINITEST_ID, 1)
        return [nil, nil] unless id

        [id, ((index + 2)...lines.size).find { |j| lines[j].chomp.match?(MINITEST_END) }]
      end

      # A block runs from "  N) description" (after the Failures: heading only) to the next such line or the summary.
      def rspec_blocks(lines)
        rspec_starts(lines).map do |i|
          last = rspec_block_end(lines, i)
          block(i, last, lines[i].chomp[RSPEC_START, 1], lines[(i + 1)..last])
        end
      end

      # Only the numbered entries under the Failures: heading, never RSpec's Pending: section.
      def rspec_starts(lines)
        failures_at = lines.index { |line| line.chomp == "Failures:" }
        return [] unless failures_at

        ((failures_at + 1)...lines.size).select { |i| lines[i].chomp.match?(RSPEC_START) }
      end

      # Stops before the next failure or the summary, then backs over the blank lines in between.
      def rspec_block_end(lines, start)
        stop = ((start + 1)...lines.size).find { |j| lines[j].chomp.match?(RSPEC_END) } || lines.size
        stop -= 1 while stop > start + 1 && lines[stop - 1].strip.empty?
        stop - 1
      end

      def block(first, last, id, body)
        key = body.map(&:chomp).reject { |line| line.strip.empty? || line.match?(IGNORED) }
        { first: first, last: last, id: id, key: key }
      end

      def rewrite(lines, blocks)
        skipped = {}
        notes = {}
        blocks.group_by { |b| b[:key] }.each_value do |kept, *dropped|
          next if dropped.empty?

          dropped.each { |b| skip_block(lines, b, skipped) }
          notes[kept[:last]] = note_for(dropped)
        end
        render(lines, skipped, notes)
      end

      def render(lines, skipped, notes)
        lines.each_with_index.reject { |_, j| skipped[j] }.map { |line, j| attach_note(line, notes[j]) }.join
      end

      # The blank line that separates the dropped block from the next one goes with it.
      def skip_block(lines, dropped, skipped)
        (dropped[:first]..dropped[:last]).each { |j| skipped[j] = true }
        skipped[dropped[:last] + 1] = true if lines[dropped[:last] + 1]&.strip&.empty?
      end

      def note_for(dropped)
        noun = dropped.size == 1 ? "test" : "tests"
        "#{dropped.size} more #{noun} failed with this same error: #{dropped.map { |b| b[:id] }.join(", ")}"
      end

      def attach_note(line, note)
        return line unless note

        "#{line.chomp}\n#{note}\n"
      end
    end
  end
end
