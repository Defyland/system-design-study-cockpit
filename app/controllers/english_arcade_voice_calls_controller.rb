# frozen_string_literal: true

class EnglishArcadeVoiceCallsController < ApplicationController
  class_attribute :voice_budget_factory, :voice_client_factory, instance_accessor: false
  self.voice_budget_factory = ->(configuration) { EnglishArcadeVoice::Budget.new(configuration: configuration) }
  self.voice_client_factory = ->(configuration) { EnglishArcadeVoice::RealtimeCallsClient.new(configuration: configuration) }

  MAX_SDP_BYTES = 256.kilobytes
  MAX_IDENTIFIER_BYTES = 256

  ERROR_STATUS = {
    voice_unavailable: :service_unavailable,
    invalid_sdp: :unprocessable_entity,
    invalid_model: :unprocessable_entity,
    session_not_found: :not_found,
    guided_session_required: :forbidden,
    session_inactive: :unprocessable_entity,
    card_not_found: :unprocessable_entity,
    budget_exhausted: :too_many_requests,
    upstream_unavailable: :bad_gateway
  }.freeze

  def create
    configuration = voice_configuration
    return error_response(:voice_unavailable) unless configuration.available?

    payload = voice_payload
    offer = payload[:sdp].to_s
    return error_response(:invalid_sdp) if offer.strip.empty? || offer.bytesize > MAX_SDP_BYTES

    selected_model = configuration.model_for(payload[:model])
    return error_response(:invalid_model) unless selected_model

    arcade_session = owned_session(payload[:session_id])
    return error_response(:session_not_found) unless arcade_session

    metadata = arcade_session.metadata.to_h.deep_stringify_keys
    return error_response(:guided_session_required) unless metadata["experience"] == "guided"
    return error_response(:session_inactive) unless arcade_session.active? && !arcade_session.expired?

    card_key = payload[:card_key].to_s.strip
    return error_response(:card_not_found) if card_key.blank? || card_key.bytesize > MAX_IDENTIFIER_BYTES
    return error_response(:card_not_found) unless card_belongs_to_session?(card_key, metadata)

    builder = EnglishArcadeSessionBuilder.new
    card = builder.card_for(
      target: arcade_session.target,
      card_key: card_key,
      session: arcade_session,
      variant_id: builder.variant_id_for(metadata.fetch("exercise", "initial"))
    )
    return error_response(:card_not_found) unless card

    budget = voice_budget(configuration)
    reservation = budget.reserve(
      learner_key: learner_key,
      seconds: configuration.call_duration_seconds
    )
    return error_response(:budget_exhausted) unless reservation

    answer = voice_client(configuration).create_call(
      sdp: offer,
      model: selected_model,
      instructions: EnglishArcadeVoice::SessionPrompt.for(card)
    )

    response.set_header("X-English-Arcade-Voice-Model", selected_model)
    response.set_header("X-English-Arcade-Voice-Call-Limit-Seconds", configuration.call_duration_seconds.to_s)
    response.set_header("X-English-Arcade-Voice-Daily-Limit-Seconds", configuration.daily_duration_seconds.to_s)
    response.set_header("Cache-Control", "no-store")
    render plain: answer, content_type: "text/sdp"
  rescue EnglishArcadeVoice::RealtimeCallsClient::UpstreamError
    budget&.release(reservation)
    error_response(:upstream_unavailable)
  rescue EnglishArcadeVoice::RealtimeCallsClient::ConfigurationUnavailable
    budget&.release(reservation)
    error_response(:voice_unavailable)
  rescue EnglishArcadeVoice::RealtimeCallsClient::InvalidRequest
    budget&.release(reservation)
    error_response(:invalid_sdp)
  rescue StandardError
    # An unexpected transport/application failure must not turn into a body or
    # exception message disclosure. The paid reservation is returned because
    # no successful upstream SDP was delivered.
    budget&.release(reservation)
    error_response(:upstream_unavailable)
  end

  private

  def voice_payload
    params.permit(:sdp, :session_id, :card_key, :model)
  end

  def owned_session(session_id)
    value = session_id.to_s.strip
    return if value.blank? || value.bytesize > MAX_IDENTIFIER_BYTES

    EnglishArcadeSession.find_by(id: value, learner_key: learner_key)
  end

  def learner_key
    # Match the cockpit's current Basic-auth identity boundary without ever
    # persisting credentials. Local/test requests use the anonymous fallback.
    request.get_header("REMOTE_USER").presence || ENV["STUDY_COCKPIT_USERNAME"].presence || "anonymous"
  end

  def card_belongs_to_session?(card_key, metadata)
    scheduled_key = metadata["scheduled_card_key"].to_s.presence
    return card_key == scheduled_key if scheduled_key

    required_keys = Array(metadata["required_card_keys"]).map(&:to_s)
    required_keys.empty? || required_keys.include?(card_key)
  end

  def voice_configuration
    EnglishArcadeVoice::Configuration.new
  end

  def voice_budget(configuration)
    self.class.voice_budget_factory.call(configuration)
  end

  def voice_client(configuration)
    self.class.voice_client_factory.call(configuration)
  end

  def error_response(code)
    response.set_header("Cache-Control", "no-store")
    render json: { error: code.to_s }, status: ERROR_STATUS.fetch(code)
  end
end
