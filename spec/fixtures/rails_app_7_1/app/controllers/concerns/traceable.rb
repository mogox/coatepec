# Empty marker concern, included on ApplicationController (not on any leaf
# controller) so that Coatepec::Introspection::Controller#concerns is
# exercised on its inherited path, not only the own-concern path every other
# fixture concern covers. Deliberately has no callbacks and no methods, public
# or private: either would perturb WidgetsController's other assertions (a
# public method would register as a routable action; a callback would join
# every controller's callback chain).
module Traceable
  extend ActiveSupport::Concern
end
