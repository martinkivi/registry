class Ability
  include CanCan::Ability
  # rubocop: disable Metrics/CyclomaticComplexity
  # rubocop: disable Metrics/PerceivedComplexity
  # rubocop: disable Metrics/LineLength
  # rubocop: disable Metrics/AbcSize
  def initialize(user)
    alias_action :show, to: :view
    alias_action :show, :create, :update, :destroy, to: :crud

    @user = user || User.new

    case @user.class.to_s
    when 'AdminUser'
      @user.roles.each { |role| send(role) } if @user.roles
    when 'ApiUser'
      @user.roles.each { |role| send(role) } if @user.roles
    when 'RegistrantUser'
      static_registrant
    end

    # Public user
    can :show, :dashboard
    can :create, :registrant_domain_update_confirm
  end

  #
  # User roles
  #

  def super # Registrar/api_user dynamic role
    static_registrar
    epp
    billing
  end

  def epp # Registrar/api_user dynamic role
    static_registrar

    # REPP
    can(:manage, :repp)

    # EPP
    can(:create, :epp_login) # billing can establis epp connection in order to login
    can(:create, :epp_request)

    # Epp::Domain
    can(:info,     Epp::Domain) { |d, pw| d.registrar_id == @user.registrar_id || pw.blank? ? true : d.auth_info == pw }
    can(:check,    Epp::Domain)
    can(:create,   Epp::Domain)
    can(:renew,    Epp::Domain) { |d| d.registrar_id == @user.registrar_id }
    can(:update,   Epp::Domain) { |d, pw| d.registrar_id == @user.registrar_id || d.auth_info == pw }
    can(:transfer, Epp::Domain) { |d, pw| d.auth_info == pw }
    can(:view_password, Epp::Domain) { |d, pw| d.registrar_id == @user.registrar_id || d.auth_info == pw }
    can(:delete,   Epp::Domain) { |d, pw| d.registrar_id == @user.registrar_id || d.auth_info == pw }

    # Epp::Contact
    can(:info, Epp::Contact)           { |c, pw| c.registrar_id == @user.registrar_id || pw.blank? ? true : c.auth_info == pw }
    can(:view_full_info, Epp::Contact) { |c, pw| c.registrar_id == @user.registrar_id || c.auth_info == pw }
    can(:check,  Epp::Contact)
    can(:create, Epp::Contact)
    can(:update, Epp::Contact) { |c, pw| c.registrar_id == @user.registrar_id || c.auth_info == pw }
    can(:delete, Epp::Contact) { |c, pw| c.registrar_id == @user.registrar_id || c.auth_info == pw }
    can(:renew,  Epp::Contact)
    can(:view_password, Epp::Contact) { |c, pw| c.registrar_id == @user.registrar_id || c.auth_info == pw }
  end

  def billing # Registrar/api_user dynamic role
    can :view, :registrar_dashboard
    can(:manage, Invoice) { |i| i.buyer_id == @user.registrar_id }
    can :manage, :deposit
    can :read, AccountActivity
    can(:create, :epp_login) # billing can establis epp connection in order to login
  end

  def customer_service # Admin/admin_user dynamic role
    user
    can :manage, Domain
    can :manage, Contact
    can :manage, Registrar
  end

  def admin # Admin/admin_user dynamic role
    customer_service
    can :manage, Setting
    can :manage, BlockedDomain
    can :manage, ReservedDomain
    can :manage, ZonefileSetting
    can :manage, DomainVersion
    can :manage, Pricelist
    can :manage, User
    can :manage, ApiUser
    can :manage, AdminUser
    can :manage, Certificate
    can :manage, Keyrelay
    can :manage, LegalDocument
    can :manage, BankStatement
    can :manage, BankTransaction
    can :manage, MailTemplate
    can :manage, Invoice
    can :manage, WhiteIp
    can :read, ApiLog::EppLog
    can :read, ApiLog::ReppLog
    can :update, :pending
    can :destroy, :pending
    can :create, :zonefile
    can :access, :settings_menu
  end

  #
  # Static roles, linked from dynamic roles
  #
  def static_registrar
    can :manage, Nameserver
    can :view, :registrar_dashboard
    can :delete, :registrar_poll
    can :manage, :registrar_xml_console
    can :manage, Depp::Contact
    can :manage, Depp::Domain
    can :renew,  Depp::Domain
    can :transfer, Depp::Domain
    can :manage, Depp::Keyrelay
    can :confirm, :keyrelay
    can :confirm, :transfer
  end

  def static_registrant
    can :manage, :registrant_domains
    can :manage, :registrant_whois
    can :manage, Depp::Domain
  end

  def user
    can :show, :dashboard
  end

  # rubocop: enable Metrics/LineLength
  # rubocop: enable Metrics/CyclomaticComplexity
  # rubocop: enable Metrics/PerceivedComplexity
end
