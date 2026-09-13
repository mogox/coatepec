# frozen_string_literal: true

require "spec_helper"
require "coatepec/spec/failure_collapser"

RSpec.describe Coatepec::Spec::FailureCollapser do
  # Rails' TestUnitReporter shape: Error:/Failure: header, test id, body, blank, rerun line.
  let(:minitest_text) do
    <<~TEXT
      Run options: --seed 11872

      # Running:

      ...E

      Error:
      EventsControllerTest#test_should_show_event:
      ActionView::Template::Error: Vite Ruby can't find entrypoints/application.js in the manifests.

      Possible causes:
        - The last build failed.


          app/views/layouts/application.html.erb:24
          test/controllers/events_controller_test.rb:25:in 'block in <class:EventsControllerTest>'

      bin/rails test test/controllers/events_controller_test.rb:24

      .E

      Error:
      EventsControllerTest#test_should_show_event_talks:
      ActionView::Template::Error: Vite Ruby can't find entrypoints/application.js in the manifests.

      Possible causes:
        - The last build failed.


          app/views/layouts/application.html.erb:24
          test/controllers/events_controller_test.rb:30:in 'block in <class:EventsControllerTest>'

      bin/rails test test/controllers/events_controller_test.rb:29

      F

      Failure:
      EventsControllerTest#test_should_get_index [test/controllers/events_controller_test.rb:12]:
      Expected: 200
        Actual: 500

      bin/rails test test/controllers/events_controller_test.rb:10

      Finished in 4.518412s, 1.9919 runs/s, 3.3198 assertions/s.
      9 runs, 15 assertions, 1 failures, 2 errors, 0 skips
    TEXT
  end

  let(:rspec_text) do
    <<~TEXT
      ...FFF

      Failures:

        1) EventsController GET show renders
           Failure/Error: get event_path(event)

           ActionView::Template::Error:
             Vite Ruby can't find entrypoints/application.js in the manifests.
           # ./app/views/layouts/application.html.erb:24:in 'block in render'
           # ./spec/requests/events_spec.rb:12:in 'block (3 levels) in <top (required)>'

        2) EventsController GET index renders
           Failure/Error: get events_path

           ActionView::Template::Error:
             Vite Ruby can't find entrypoints/application.js in the manifests.
           # ./app/views/layouts/application.html.erb:24:in 'block in render'
           # ./spec/requests/events_spec.rb:7:in 'block (3 levels) in <top (required)>'

        3) Widget is valid
           Failure/Error: expect(widget).to be_valid
             expected #<Widget> to be valid
           # ./spec/models/widget_spec.rb:5:in 'block (2 levels) in <top (required)>'

      Finished in 0.5 seconds (files took 1.2 seconds to load)
      3 examples, 3 failures

      Failed examples:

      rspec ./spec/requests/events_spec.rb:11 # EventsController GET show renders
      rspec ./spec/requests/events_spec.rb:6 # EventsController GET index renders
      rspec ./spec/models/widget_spec.rb:4 # Widget is valid
    TEXT
  end

  # The second Minitest block, from its Error: header through its rerun line.
  let(:talks_block) { /Error:\nEventsControllerTest#test_should_show_event_talks:.*?events_controller_test.rb:29\n/m }

  it "keeps the first Minitest block and rolls later identical errors into one line" do
    result = described_class.call(minitest_text)
    rollup = "1 more test failed with this same error: EventsControllerTest#test_should_show_event_talks\n"

    expect(result.scan("Vite Ruby can't find").size).to eq(1)
    expect(result).to include("bin/rails test test/controllers/events_controller_test.rb:24\n#{rollup}")
    expect(result).not_to include("events_controller_test.rb:29")
  end

  it "ends a Minitest block on a bare \"rails test path:LINE\" rerun line too" do
    result = described_class.call(minitest_text.gsub("bin/rails test ", "rails test "))
    rollup = "1 more test failed with this same error: EventsControllerTest#test_should_show_event_talks\n"

    expect(result.scan("Vite Ruby can't find").size).to eq(1)
    expect(result).to include("rails test test/controllers/events_controller_test.rb:24\n#{rollup}")
    expect(result).not_to include("events_controller_test.rb:29")
  end

  it "leaves a Minitest block with a different error, the progress marks and the summary untouched" do
    result = described_class.call(minitest_text)
    header = "Failure:\nEventsControllerTest#test_should_get_index " \
             "[test/controllers/events_controller_test.rb:12]:\n"

    expect(result).to include("#{header}Expected: 200\n  Actual: 500\n")
    expect(result).to include("# Running:\n\n...E\n")
    expect(result).to end_with("9 runs, 15 assertions, 1 failures, 2 errors, 0 skips\n")
  end

  it "collapses RSpec failures by exception text, ignoring the Failure/Error source line and frames" do
    result = described_class.call(rspec_text)

    expect(result.scan("Vite Ruby can't find").size).to eq(1)
    expect(result).to include("events_spec.rb:12:in 'block (3 levels) in <top (required)>'\n" \
                              "1 more test failed with this same error: EventsController GET index renders\n")
    expect(result).not_to include("2) EventsController GET index renders")
    expect(result).to include("3) Widget is valid")
    expect(result).to include("rspec ./spec/requests/events_spec.rb:6 # EventsController GET index renders")
  end

  it "pluralises the roll-up and lists every dropped test in order" do
    third = minitest_text[talks_block]
            .gsub("test_should_show_event_talks", "test_should_show_event_events")
            .gsub("events_controller_test.rb:30", "events_controller_test.rb:35")
            .gsub("events_controller_test.rb:29", "events_controller_test.rb:34")
    text = minitest_text.sub("\nF\n", "\n#{third}\nF\n")

    result = described_class.call(text)
    dropped = "EventsControllerTest#test_should_show_event_talks, " \
              "EventsControllerTest#test_should_show_event_events\n"

    expect(result).to include("2 more tests failed with this same error: #{dropped}")
  end

  it "returns the text unchanged when only one failure block is present" do
    text = minitest_text.sub(/#{talks_block}\n/, "")

    expect(described_class.call(text)).to eq(text)
  end

  it "returns the text unchanged when no block shares an error" do
    text = minitest_text.sub("test/controllers/events_controller_test.rb:30:in", "x")
                        .sub("Vite Ruby can't find entrypoints", "Cannot open")

    expect(described_class.call(text)).to eq(text)
  end

  it "returns unrecognised text unchanged" do
    text = "1 example, 0 failures\n"

    expect(described_class.call(text)).to eq(text)
  end

  it "never collapses RSpec's Pending section" do
    text = <<~TEXT
      Pending: (Failures listed here are expected and do not affect your suite's status)

        1) A does x
           # Not yet implemented
           # ./spec/a_spec.rb:3

        2) B does y
           # Not yet implemented
           # ./spec/b_spec.rb:3

      Finished in 0.01 seconds (files took 0.1 seconds to load)
      2 examples, 0 failures, 2 pending
    TEXT

    expect(described_class.call(text)).to eq(text)
  end
end
