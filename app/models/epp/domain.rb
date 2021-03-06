# rubocop: disable Metrics/ClassLength
class Epp::Domain < Domain
  include EppErrors

  before_validation :manage_permissions
  def manage_permissions
    return unless update_prohibited? || delete_prohibited?
    add_epp_error('2304', nil, nil, I18n.t(:object_status_prohibits_operation))
    false
  end

  before_validation :validate_contacts
  def validate_contacts
    return if contacts.map(&:valid?).all?
    add_epp_error('2304', nil, nil, I18n.t(:object_status_prohibits_operation))
    false
  end

  before_save :link_contacts
  def link_contacts
    # Based on bullet report
    unlinked_contacts = contacts.select { |c| !c.linked? } # speed up a bit
    unlinked_contacts.each do |uc|
      uc.domains_present = true # no need to fetch domains again
      uc.save(validate: false)
    end
  end

  after_destroy :unlink_contacts
  def unlink_contacts
    contacts.each do |c|
      c.domains_present = false
      c.save(validate: false)
    end
  end

  class << self
    def new_from_epp(frame, current_user)
      domain = Epp::Domain.new
      domain.attributes = domain.attrs_from(frame, current_user)
      domain.attach_default_contacts
      domain
    end
  end

  def epp_code_map # rubocop:disable Metrics/MethodLength
    {
      '2002' => [ # Command use error
        [:base, :domain_already_belongs_to_the_querying_registrar]
      ],
      '2003' => [ # Required parameter missing
        [:registrant, :blank],
        [:registrar, :blank],
        [:base, :required_parameter_missing_reserved]
      ],
      '2004' => [ # Parameter value range error
        [:nameservers, :out_of_range,
         {
           min: Setting.ns_min_count,
           max: Setting.ns_max_count
         }
        ],
        [:dnskeys, :out_of_range,
         {
           min: Setting.dnskeys_min_count,
           max: Setting.dnskeys_max_count
         }
        ],
        [:admin_contacts, :out_of_range,
         {
           min: Setting.admin_contacts_min_count,
           max: Setting.admin_contacts_max_count
         }
        ],
        [:tech_contacts, :out_of_range,
         {
           min: Setting.tech_contacts_min_count,
           max: Setting.tech_contacts_max_count
         }
        ]
      ],
      '2005' => [ # Parameter value syntax error
        [:name_dirty, :invalid, { obj: 'name', val: name_dirty }],
        [:puny_label, :too_long, { obj: 'name', val: name_puny }]
      ],
      '2201' => [ # Authorisation error
        [:auth_info, :wrong_pw]
      ],
      '2202' => [
        [:base, :invalid_auth_information_reserved]
      ],
      '2302' => [ # Object exists
        [:name_dirty, :taken, { value: { obj: 'name', val: name_dirty } }],
        [:name_dirty, :reserved, { value: { obj: 'name', val: name_dirty } }],
        [:name_dirty, :blocked, { value: { obj: 'name', val: name_dirty } }]
      ],
      '2304' => [ # Object status prohibits operation
        [:base, :domain_status_prohibits_operation]
      ],
      '2306' => [ # Parameter policy error
        [:period, :out_of_range, { value: { obj: 'period', val: period } }],
        [:base, :ds_data_with_key_not_allowed],
        [:base, :ds_data_not_allowed],
        [:base, :key_data_not_allowed],
        [:period, :not_a_number],
        [:period, :not_an_integer]
      ],
      '2308' => [
        [:base, :domain_name_blocked, { value: { obj: 'name', val: name_dirty } }]
      ]
    }
  end

  def attach_default_contacts
    return if registrant.blank?
    regt = Registrant.find(registrant.id) # temp for bullet
    tech_contacts << regt if tech_domain_contacts.blank?
    admin_contacts << regt if admin_domain_contacts.blank? && regt.priv?
  end

  # rubocop: disable Metrics/PerceivedComplexity
  # rubocop: disable Metrics/CyclomaticComplexity
  # rubocop: disable Metrics/MethodLength
  # rubocop: disable Metrics/AbcSize
  def attrs_from(frame, current_user, action = nil)
    at = {}.with_indifferent_access

    code = frame.css('registrant').first.try(:text)
    if code.present?
      regt = Registrant.find_by(code: code)
      if regt
        at[:registrant_id] = regt.id
      else
        add_epp_error('2303', 'registrant', code, [:registrant, :not_found])
      end
    end

    at[:name] = frame.css('name').text if new_record?
    at[:registrar_id] = current_user.registrar.try(:id)
    at[:registered_at] = Time.zone.now if new_record?

    period = frame.css('period').text
    at[:period] = (period.to_i == 0) ? 1 : period.to_i

    at[:period_unit] = Epp::Domain.parse_period_unit_from_frame(frame) || 'y'

    at[:reserved_pw] = frame.css('reserved > pw').text

    # at[:statuses] = domain_statuses_attrs(frame, action)
    at[:nameservers_attributes] = nameservers_attrs(frame, action)
    at[:admin_domain_contacts_attributes] = admin_domain_contacts_attrs(frame, action)
    at[:tech_domain_contacts_attributes] = tech_domain_contacts_attrs(frame, action)
    # at[:domain_statuses_attributes] = domain_statuses_attrs(frame, action)

    pw = frame.css('authInfo > pw').text
    at[:auth_info] = pw if pw.present?

    if new_record?
      dnskey_frame = frame.css('extension create')
    else
      dnskey_frame = frame
    end

    at[:dnskeys_attributes] = dnskeys_attrs(dnskey_frame, action)
    at[:legal_documents_attributes] = legal_document_from(frame)
    at
  end
  # rubocop: enable Metrics/PerceivedComplexity
  # rubocop: enable Metrics/CyclomaticComplexity
  # rubocop: enable Metrics/MethodLength
  # rubocop: enable Metrics/AbcSize

  def nameservers_attrs(frame, action)
    ns_list = nameservers_from(frame)

    if action == 'rem'
      to_destroy = []
      ns_list.each do |ns_attrs|
        nameserver = nameservers.where(ns_attrs).try(:first)
        if nameserver.blank?
          add_epp_error('2303', 'hostAttr', ns_attrs[:hostname], [:nameservers, :not_found])
        else
          to_destroy << {
            id: nameserver.id,
            _destroy: 1
          }
        end
      end

      return to_destroy
    else
      return ns_list
    end
  end

  def nameservers_from(frame)
    res = []
    frame.css('hostAttr').each do |x|
      host_attr = {
        hostname: x.css('hostName').first.try(:text),
        ipv4: x.css('hostAddr[ip="v4"]').first.try(:text),
        ipv6: x.css('hostAddr[ip="v6"]').first.try(:text)
      }

      res << host_attr.delete_if { |_k, v| v.blank? }
    end

    res
  end

  def admin_domain_contacts_attrs(frame, action)
    admin_attrs = domain_contact_attrs_from(frame, action, 'admin')

    case action
    when 'rem'
      return destroy_attrs(admin_attrs, admin_domain_contacts)
    else
      return admin_attrs
    end
  end

  def tech_domain_contacts_attrs(frame, action)
    tech_attrs = domain_contact_attrs_from(frame, action, 'tech')

    case action
    when 'rem'
      return destroy_attrs(tech_attrs, tech_domain_contacts)
    else
      return tech_attrs
    end
  end

  def destroy_attrs(attrs, dcontacts)
    destroy_attrs = []
    attrs.each do |at|
      domain_contact_id = dcontacts.find_by(contact_id: at[:contact_id]).try(:id)

      unless domain_contact_id
        add_epp_error('2303', 'contact', at[:contact_code_cache], [:domain_contacts, :not_found])
        next
      end

      destroy_attrs << {
        id: domain_contact_id,
        _destroy: 1
      }
    end

    destroy_attrs
  end

  def domain_contact_attrs_from(frame, action, type)
    attrs = []
    frame.css('contact').each do |x|
      next if x['type'] != type

      c = Epp::Contact.find_by_epp_code(x.text)
      unless c
        add_epp_error('2303', 'contact', x.text, [:domain_contacts, :not_found])
        next
      end

      if action != 'rem'
        if x['type'] == 'admin' && c.bic?
          add_epp_error('2306', 'contact', x.text, [:domain_contacts, :admin_contact_can_be_only_private_person])
          next
        end
      end

      attrs << {
        contact_id: c.id,
        contact_code_cache: c.code
      }
    end

    attrs
  end

  # rubocop: disable Metrics/PerceivedComplexity
  # rubocop: disable Metrics/CyclomaticComplexity
  def dnskeys_attrs(frame, action)
    if frame.css('dsData').any? && !Setting.ds_data_allowed
      errors.add(:base, :ds_data_not_allowed)
    end

    if frame.xpath('keyData').any? && !Setting.key_data_allowed
      errors.add(:base, :key_data_not_allowed)
    end

    res = ds_data_from(frame)
    dnskeys_list = key_data_from(frame, res)

    if action == 'rem'
      to_destroy = []
      dnskeys_list.each do |x|
        dk = dnskeys.find_by(public_key: x[:public_key])

        unless dk
          add_epp_error('2303', 'publicKey', x[:public_key], [:dnskeys, :not_found])
          next
        end

        to_destroy << {
          id: dk.id,
          _destroy: 1
        }
      end

      return to_destroy
    else
      return dnskeys_list
    end
  end
  # rubocop: enable Metrics/PerceivedComplexity
  # rubocop: enable Metrics/CyclomaticComplexity

  def key_data_from(frame, res)
    frame.xpath('keyData').each do |x|
      res << {
        flags: x.css('flags').first.try(:text),
        protocol: x.css('protocol').first.try(:text),
        alg: x.css('alg').first.try(:text),
        public_key: x.css('pubKey').first.try(:text),
        ds_alg: 3,
        ds_digest_type: Setting.ds_algorithm
      }
    end

    res
  end

  def ds_data_from(frame)
    res = []
    frame.css('dsData').each do |x|
      data = {
        ds_key_tag: x.css('keyTag').first.try(:text),
        ds_alg: x.css('alg').first.try(:text),
        ds_digest_type: x.css('digestType').first.try(:text),
        ds_digest: x.css('digest').first.try(:text)
      }

      kd = x.css('keyData').first
      data.merge!({
        flags: kd.css('flags').first.try(:text),
        protocol: kd.css('protocol').first.try(:text),
        alg: kd.css('alg').first.try(:text),
        public_key: kd.css('pubKey').first.try(:text)
      }) if kd

      res << data
    end

    res
  end

  def domain_statuses_attrs(frame, action)
    status_list = domain_status_list_from(frame)

    if action == 'rem'
      to_destroy = []
      status_list.each do |x|
        if statuses.include?(x)
          to_destroy << x
        else
          add_epp_error('2303', 'status', x, [:domain_statuses, :not_found])
        end
      end

      return to_destroy
    else
      return status_list
    end
  end

  def domain_status_list_from(frame)
    status_list = []

    frame.css('status').each do |x|
      unless DomainStatus::CLIENT_STATUSES.include?(x['s'])
        add_epp_error('2303', 'status', x['s'], [:domain_statuses, :not_found])
        next
      end

      status_list << x['s']
    end

    status_list
  end

  def legal_document_from(frame)
    ld = frame.css('legalDocument').first
    return [] unless ld

    [{
      body: ld.text,
      document_type: ld['type']
    }]
  end

  # rubocop: disable Metrics/AbcSize
  # rubocop: disable Metrics/CyclomaticComplexity
  def update(frame, current_user, verify = true)
    return super if frame.blank?
    at = {}.with_indifferent_access
    at.deep_merge!(attrs_from(frame.css('chg'), current_user))
    at.deep_merge!(attrs_from(frame.css('rem'), current_user, 'rem'))

    at_add = attrs_from(frame.css('add'), current_user)
    at[:nameservers_attributes] += at_add[:nameservers_attributes]
    at[:admin_domain_contacts_attributes] += at_add[:admin_domain_contacts_attributes]
    at[:tech_domain_contacts_attributes] += at_add[:tech_domain_contacts_attributes]
    at[:dnskeys_attributes] += at_add[:dnskeys_attributes]
    at[:statuses] =
      statuses - domain_statuses_attrs(frame.css('rem'), 'rem') + domain_statuses_attrs(frame.css('add'), 'add')

    # at[:statuses] += at_add[:domain_statuses_attributes]

    if verify &&
       Setting.request_confrimation_on_registrant_change_enabled &&
       frame.css('registrant').present? &&
       frame.css('registrant').attr('verified').to_s.downcase != 'yes'
      registrant_verification_asked!(frame.to_s, current_user.id)
    end
    self.deliver_emails = true # turn on email delivery for epp

    errors.empty? && super(at)
  end
  # rubocop: enable Metrics/AbcSize
  # rubocop: enable Metrics/CyclomaticComplexity

  def apply_pending_update!
    old_registrant_email = DomainMailer.registrant_updated_notification_for_old_registrant(self)
    preclean_pendings
    user  = ApiUser.find(pending_json['current_user_id'])
    frame = Nokogiri::XML(pending_json['frame'])
    statuses.delete(DomainStatus::PENDING_UPDATE)

    return unless update(frame, user, false)
    clean_pendings!
    self.deliver_emails = true # turn on email delivery
    DomainMailer.registrant_updated_notification_for_new_registrant(self).deliver_now
    old_registrant_email.deliver_now
    true
  end

  def apply_pending_delete!
    preclean_pendings
    user  = ApiUser.find(pending_json['current_user_id'])
    frame = Nokogiri::XML(pending_json['frame'])
    statuses.delete(DomainStatus::PENDING_DELETE)
    DomainMailer.delete_confirmation(self).deliver_now

    clean_pendings! if epp_destroy(frame, user, false)
    true
  end

  def attach_legal_document(legal_document_data)
    return unless legal_document_data

    legal_documents.build(
      document_type: legal_document_data[:type],
      body: legal_document_data[:body]
    )
  end

  def epp_destroy(frame, user_id, verify = true)
    return false unless valid?

    if verify &&
       Setting.request_confirmation_on_domain_deletion_enabled &&
       frame.css('delete').attr('verified').to_s.downcase != 'yes'

      registrant_verification_asked!(frame.to_s, user_id)
      self.deliver_emails = true # turn on email delivery for epp
      pending_delete!
      manage_automatic_statuses
      true # aka 1001 pending_delete
    else
      set_expired!
    end
  end

  ### RENEW ###

  def renew(cur_exp_date, period, unit = 'y')
    validate_exp_dates(cur_exp_date)

    add_epp_error('2105', nil, nil, I18n.t('object_is_not_eligible_for_renewal')) unless renewable?
    return false if errors.any?

    p = self.class.convert_period_to_time(period, unit)
    self.valid_to = valid_to + p
    self.outzone_at = valid_to + Setting.expire_warning_period.days
    self.delete_at = outzone_at + Setting.redemption_grace_period.days
    self.period = period
    self.period_unit = unit

    statuses.delete(DomainStatus::SERVER_HOLD)
    statuses.delete(DomainStatus::EXPIRED)

    save
  end

  ### TRANSFER ###

  # rubocop: disable Metrics/PerceivedComplexity
  # rubocop: disable Metrics/CyclomaticComplexity
  def transfer(frame, action, current_user)
    case action
    when 'query'
      return domain_transfers.last if domain_transfers.any?
    when 'request'
      return pending_transfer if pending_transfer
      return query_transfer(frame, current_user)
    when 'approve'
      return approve_transfer(frame, current_user) if pending_transfer
    when 'reject'
      return reject_transfer(frame, current_user) if pending_transfer
    end
  end

  # TODO: Eager load problems here. Investigate how it's possible not to query contact again
  # Check if versioning works with update_column
  def transfer_contacts(registrar_id)
    transfer_registrant(registrar_id)
    transfer_domain_contacts(registrar_id)
  end

  def copy_and_transfer_contact(contact_id, registrar_id)
    c = Contact.find(contact_id) # n+1 workaround
    oc = c.deep_clone
    oc.code = nil
    oc.registrar_id = registrar_id
    oc.prefix_code
    oc.save!(validate: false)
    oc
  end

  def transfer_contact(contact_id, registrar_id)
    oc = Contact.find(contact_id) # n+1 workaround
    oc.registrar_id = registrar_id
    oc.generate_new_code!
    oc.save!(validate: false)
    oc
  end

  def transfer_registrant(registrar_id)
    return if registrant.registrar_id == registrar_id

    is_other_domains_contact = DomainContact.where('contact_id = ? AND domain_id != ?', registrant_id, id).count > 0
    if registrant.registrant_domains.count > 1 || is_other_domains_contact
      oc = copy_and_transfer_contact(registrant_id, registrar_id)
      self.registrant_id = oc.id
    else
      transfer_contact(registrant_id, registrar_id)
    end
  end

  def transfer_domain_contacts(registrar_id)
    copied_ids = []
    contacts.each do |c|
      next if copied_ids.include?(c.id) || c.registrar_id == registrar_id

      is_other_domains_contact = DomainContact.where('contact_id = ? AND domain_id != ?', c.id, id).count > 0
      # if contact used to be owner contact but was copied, then contact must be transferred
      # (registrant_id_was != c.id)
      if c.domains.count > 1 || is_other_domains_contact
        # copy contact
        if registrant_id_was == c.id # owner contact was copied previously, do not copy it again
          oc = OpenStruct.new(id: registrant_id)
        else
          oc = copy_and_transfer_contact(c.id, registrar_id)
        end

        domain_contacts.where(contact_id: c.id).update_all({ contact_id: oc.id }) # n+1 workaround
        copied_ids << c.id
      else
        transfer_contact(c.id, registrar_id)
      end
    end
  end

  # rubocop: enable Metrics/PerceivedComplexity
  # rubocop: enable Metrics/CyclomaticComplexity
  # rubocop: disable Metrics/MethodLength
  # rubocop: disable Metrics/AbcSize
  def query_transfer(frame, current_user)
    unless transferrable?
      throw :epp_error, {
        code: '2304',
        msg: I18n.t(:object_status_prohibits_operation)
      }
    end

    if current_user.registrar == registrar
      throw :epp_error, {
        code: '2002',
        msg: I18n.t(:domain_already_belongs_to_the_querying_registrar)
      }
    end

    old_contact_codes = contacts.pluck(:code).sort.uniq
    old_registrant_code = registrant.code

    transaction do
      dt = domain_transfers.create!(
        transfer_requested_at: Time.zone.now,
        transfer_to: current_user.registrar,
        transfer_from: registrar
      )

      if dt.pending?
        registrar.messages.create!(
          body: I18n.t('transfer_requested'),
          attached_obj_id: dt.id,
          attached_obj_type: dt.class.to_s
        )
      end

      if dt.approved?
        transfer_contacts(current_user.registrar_id)
        dt.notify_losing_registrar(old_contact_codes, old_registrant_code)
        generate_auth_info!
        self.registrar = current_user.registrar
      end

      attach_legal_document(self.class.parse_legal_document_from_frame(frame))
      save!(validate: false)

      return dt
    end
  end
  # rubocop: enable Metrics/AbcSize
  # rubocop: enable Metrics/MethodLength

  def approve_transfer(frame, current_user)
    pt = pending_transfer
    if current_user.registrar != pt.transfer_from
      throw :epp_error, {
        msg: I18n.t('transfer_can_be_approved_only_by_current_registrar'),
        code: '2304'
      }
    end

    transaction do
      pt.update!(
        status: DomainTransfer::CLIENT_APPROVED,
        transferred_at: Time.zone.now
      )

      transfer_contacts(pt.transfer_to_id)
      generate_auth_info
      self.registrar = pt.transfer_to

      attach_legal_document(self.class.parse_legal_document_from_frame(frame))
      save!(validate: false)
    end

    pt
  end

  def reject_transfer(frame, current_user)
    pt = pending_transfer
    if current_user.registrar != pt.transfer_from
      throw :epp_error, {
        msg: I18n.t('transfer_can_be_rejected_only_by_current_registrar'),
        code: '2304'
      }
    end

    transaction do
      pt.update!(
        status: DomainTransfer::CLIENT_REJECTED
      )

      attach_legal_document(self.class.parse_legal_document_from_frame(frame))
      save!(validate: false)
    end

    pt
  end

  # rubocop:disable Metrics/MethodLength
  # rubocop:disable Metrics/AbcSize
  def keyrelay(parsed_frame, requester)
    if registrar == requester
      errors.add(:base, :domain_already_belongs_to_the_querying_registrar) and return false
    end

    abs_datetime = parsed_frame.css('absolute').text
    abs_datetime = DateTime.zone.parse(abs_datetime) if abs_datetime.present?

    transaction do
      kr = keyrelays.build(
        pa_date: Time.zone.now,
        key_data_flags: parsed_frame.css('flags').text,
        key_data_protocol: parsed_frame.css('protocol').text,
        key_data_alg: parsed_frame.css('alg').text,
        key_data_public_key: parsed_frame.css('pubKey').text,
        auth_info_pw: parsed_frame.css('pw').text,
        expiry_relative: parsed_frame.css('relative').text,
        expiry_absolute: abs_datetime,
        requester: requester,
        accepter: registrar
      )

      legal_document_data = self.class.parse_legal_document_from_frame(parsed_frame)
      if legal_document_data
        kr.legal_documents.build(
          document_type: legal_document_data[:type],
          body: legal_document_data[:body]
        )
      end

      kr.save

      return false unless valid?

      registrar.messages.create!(
        body: 'Key Relay action completed successfully.',
        attached_obj_type: kr.class.to_s,
        attached_obj_id: kr.id
      )
    end

    true
  end
  # rubocop:enable Metrics/AbcSize
  # rubocop:enable Metrics/MethodLength

  ### VALIDATIONS ###

  def validate_exp_dates(cur_exp_date)
    begin
      return if cur_exp_date.to_date == valid_to.to_date
    rescue
      add_epp_error('2306', 'curExpDate', cur_exp_date, I18n.t('errors.messages.epp_exp_dates_do_not_match'))
      return
    end
    add_epp_error('2306', 'curExpDate', cur_exp_date, I18n.t('errors.messages.epp_exp_dates_do_not_match'))
  end

  ### ABILITIES ###
  def can_be_deleted?
    begin
      errors.add(:base, :domain_status_prohibits_operation)
      return false
    end if statuses.include?(DomainStatus::CLIENT_DELETE_PROHIBITED)

    true
  end

  def transferrable?
    (statuses & [
      DomainStatus::PENDING_CREATE,
      DomainStatus::PENDING_UPDATE,
      DomainStatus::PENDING_DELETE,
      DomainStatus::PENDING_RENEW,
      DomainStatus::PENDING_TRANSFER,
      DomainStatus::FORCE_DELETE
    ]).empty?
  end

  ## SHARED

  # For domain transfer
  def authenticate(pw)
    errors.add(:auth_info, :wrong_pw) if pw != auth_info
    errors.empty?
  end

  class << self
    def parse_period_unit_from_frame(parsed_frame)
      p = parsed_frame.css('period').first
      return nil unless p
      p[:unit]
    end

    def parse_legal_document_from_frame(parsed_frame)
      ld = parsed_frame.css('legalDocument').first
      return nil unless ld

      {
        body: ld.text,
        type: ld['type']
      }
    end

    def check_availability(domains)
      domains = [domains] if domains.is_a?(String)

      res = []
      domains.each do |x|
        x.strip!
        x.downcase!
        unless DomainNameValidator.validate_format(x)
          res << { name: x, avail: 0, reason: 'invalid format' }
          next
        end

        if ReservedDomain.pw_for(x).present?
          res << { name: x, avail: 0, reason: I18n.t('errors.messages.epp_domain_reserved') }
          next
        end

        if Domain.find_by(name: x)
          res << { name: x, avail: 0, reason: 'in use' }
        else
          res << { name: x, avail: 1 }
        end
      end

      res
    end
  end
end
# rubocop: enable Metrics/ClassLength
