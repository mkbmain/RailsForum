Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self
    policy.img_src     :self, :data, :https  # :https covers OAuth avatar URLs
    policy.object_src  :none
    policy.script_src  :self
    policy.style_src   :self
    policy.connect_src :self, "wss:"         # Action Cable WebSocket
    policy.frame_ancestors :none             # clickjacking protection
  end

  # Generate a per-request nonce for inline scripts (dark mode toggle, importmap).
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
