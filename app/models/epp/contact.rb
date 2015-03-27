# rubocop: disable Metrics/ClassLength
class Epp::Contact < Contact
  include EppErrors

  # disable STI, there is type column present
  self.inheritance_column = :sti_disabled

  class << self
    # rubocop: disable Metrics/PerceivedComplexity
    # rubocop: disable Metrics/CyclomaticComplexity
    # rubocop: disable Metrics/MethodLength
    def attrs_from(frame)
      f = frame
      at = {}.with_indifferent_access
      at[:name]     = f.css('postalInfo name').text if f.css('postalInfo name').present? 
      at[:org_name] = f.css('postalInfo org').text  if f.css('postalInfo org').present? 
      at[:email]    = f.css('email').text           if f.css('email').present?
      at[:fax]      = f.css('fax').text             if f.css('fax').present?
      at[:phone]    = f.css('voice').text           if f.css('voice').present?
      at[:auth_info] = f.css('authInfo pw').text if f.css('authInfo pw').present? 
      at[:address_attributes] = {}.with_indifferent_access
      sat = at[:address_attributes]
      sat[:city]   = f.css('postalInfo addr city').text   if f.css('postalInfo addr city').present?
      sat[:zip]    = f.css('postalInfo addr pc').text     if f.css('postalInfo addr pc').present?
      sat[:street] = f.css('postalInfo addr street').text if f.css('postalInfo addr street').present?
      sat[:state]  = f.css('postalInfo addr sp').text     if f.css('postalInfo addr sp').present?
      sat[:country_code] = f.css('postalInfo addr cc').text if f.css('postalInfo addr cc').present?
      at.delete(:address_attributes) if at[:address_attributes].blank?

      legal_frame = f.css('legalDocument').first
      if legal_frame.present?
        at[:legal_documents_attributes] = legal_document_attrs(legal_frame) 
      end
      at.merge!(ident_attrs(f.css('ident').first))
      at
    end
    # rubocop: enable Metrics/MethodLength
    # rubocop: enable Metrics/PerceivedComplexity
    # rubocop: enable Metrics/CyclomaticComplexity

    def new(frame, registrar)
      return super if frame.blank?

      custom_code = 
        if frame.css('id').text.present?
          "#{registrar.code}:#{frame.css('id').text.parameterize}"
        else
          nil
        end

      super(
        attrs_from(frame).merge(
          code: custom_code,
          registrar: registrar
        )
      )
    end

    def ident_attrs(ident_frame)
      return {} if ident_frame.blank?
      return {} if ident_frame.try('text').blank?
      return {} if ident_frame.attr('type').blank?
      return {} if ident_frame.attr('cc').blank?

      {
        ident: ident_frame.text,
        ident_type: ident_frame.attr('type'),
        ident_country_code: ident_frame.attr('cc')
      }
    end

    def legal_document_attrs(legal_frame)
      return [] if legal_frame.blank?
      return [] if legal_frame.try('text').blank?
      return [] if legal_frame.attr('type').blank?

      [{
        body: legal_frame.text,
        document_type: legal_frame.attr('type')
      }]
    end
  end

  def epp_code_map # rubocop:disable Metrics/MethodLength
    {
      '2302' => [ # Object exists
        [:code, :epp_id_taken]
      ],
      '2305' => [ # Association exists
        [:domains, :exist]
      ],
      '2005' => [ # Value syntax error
        [:phone, :invalid],
        [:email, :invalid],
        [:ident, :invalid],
        [:ident, :invalid_EE_identity_format],
        [:ident, :invalid_birthday_format]
      ]
    }
  end

  def update_attributes(frame)
    return super if frame.blank?
    at = {}.with_indifferent_access
    at.deep_merge!(self.class.attrs_from(frame.css('chg')))
    at.merge!(self.class.ident_attrs(frame.css('ident').first))
    legal_frame = frame.css('legalDocument').first
    at[:legal_documents_attributes] = self.class.legal_document_attrs(legal_frame) 

    super(at)
  end
end
# rubocop: enable Metrics/ClassLength
