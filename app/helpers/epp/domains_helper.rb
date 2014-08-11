module Epp::DomainsHelper
  def create_domain
    Domain.transaction do
      @domain = Domain.new(domain_create_params)

      handle_errors(@domain) and return unless @domain.attach_objects(@ph, params[:frame])
      handle_errors(@domain) and return unless @domain.save

      render '/epp/domains/create'
    end
  end

  def check_domain
    ph = params_hash['epp']['command']['check']['check']
    @domains = Domain.check_availability(ph[:name])
    render '/epp/domains/check'
  end

  def renew_domain
    # TODO support period unit
    @domain = find_domain

    handle_errors(@domain) and return unless @domain
    handle_errors(@domain) and return unless @domain.renew(@ph[:curExpDate], @ph[:period])

    render '/epp/domains/renew'
  end

  ### HELPER METHODS ###
  private

  ## CREATE
  def validate_domain_create_request
    @ph = params_hash['epp']['command']['create']['create']
    xml_attrs_present?(@ph, [['name'], ['ns'], ['authInfo'], ['contact'], ['registrant']])
  end

  def domain_create_params
    {
      name: @ph[:name],
      registrar_id: current_epp_user.registrar.try(:id),
      registered_at: Time.now,
      period: @ph[:period].to_i,
      valid_from: Date.today,
      valid_to: Date.today + @ph[:period].to_i.years,
      auth_info: @ph[:authInfo][:pw]
    }
  end

  ## RENEW
  def validate_domain_renew_request
    @ph = params_hash['epp']['command']['renew']['renew']
    xml_attrs_present?(@ph, [['name'], ['curExpDate'], ['period']])
  end

  ## SHARED
  def find_domain
    domain = Domain.find_by(name: @ph[:name])
    unless domain
      epp_errors << {code: '2303', msg: I18n.t('errors.messages.epp_domain_not_found'), value: {obj: 'name', val: @ph[:name]}}
    end
    domain
  end
end
