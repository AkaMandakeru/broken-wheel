# frozen_string_literal: true

# Without an explicit expiry Rails issues a *browser-session* cookie: it dies
# when the browser session ends, which on a phone happens constantly. Together
# with Devise's 30-minute :timeoutable (since removed) that is what made people
# sign in again so often.
#
# The key must stay exactly as Rails derived it from the application name —
# changing it would invalidate every session in flight and sign everyone out, so
# the fix for premature logouts would start with one.
Rails.application.config.session_store :cookie_store,
                                       key: "_sports_communities_session",
                                       expire_after: 30.days
