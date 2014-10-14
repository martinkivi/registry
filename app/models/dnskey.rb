class Dnskey < ActiveRecord::Base
  include EppErrors

  belongs_to :domain

  validates :alg, :protocol, :flags, :public_key, presence: true
  validate :validate_algorithm
  validate :validate_protocol
  validate :validate_flags

  before_save -> { generate_digest unless ds_digest.present? }

  ALGORITHMS = %w(3 5 6 7 8 252 253 254 255)
  PROTOCOLS = %w(3)
  FLAGS = %w(0 256 257)

  def epp_code_map
    {
      '2005' => [
        [:alg, :invalid, { value: { obj: 'alg', val: alg }, values: ALGORITHMS.join(', ') }],
        [:protocol, :invalid, { value: { obj: 'protocol', val: protocol }, values: PROTOCOLS.join(', ') }],
        [:flags, :invalid, { value: { obj: 'flags', val: flags }, values: FLAGS.join(', ') }]
      ],
      '2302' => [
        [:public_key, :taken, { value: { obj: 'pubKey', val: public_key } }]
      ],
      '2303' => [
        [:base, :dnskey_not_found, { value: { obj: 'pubKey', val: public_key } }]
      ],
      '2306' => [
        [:alg, :blank],
        [:protocol, :blank],
        [:flags, :blank],
        [:public_key, :blank]
      ]
    }
  end

  def validate_algorithm
    return if alg.blank?
    return if ALGORITHMS.include?(alg.to_s)
    errors.add(:alg, :invalid, values: ALGORITHMS.join(', '))
  end

  def validate_protocol
    return if protocol.blank?
    return if PROTOCOLS.include?(protocol.to_s)
    errors.add(:protocol, :invalid, values: PROTOCOLS.join(', '))
  end

  def validate_flags
    return if flags.blank?
    return if FLAGS.include?(flags.to_s)
    errors.add(:flags, :invalid, values: FLAGS.join(', '))
  end

  def generate_digest
    flags_hex = self.class.int_to_hex(flags)
    protocol_hex = self.class.int_to_hex(protocol)
    alg_hex = self.class.int_to_hex(alg)

    hex = [domain.name_in_wire_format, flags_hex, protocol_hex, alg_hex, public_key_hex].join
    bin = self.class.hex_to_bin(hex)
    self.ds_digest = Digest::SHA256.hexdigest(bin).upcase
  end

  def public_key_hex
    self.class.bin_to_hex(Base64.decode64(public_key))
  end

  class << self
    def int_to_hex(s)
      s = s.to_s(16)
      s.prepend('0') if s.length.odd?
    end

    def hex_to_bin(s)
      s.scan(/../).map(&:hex).pack('c*')
    end

    def bin_to_hex(s)
      s.each_byte.map { |b| sprintf('%02X', b) }.join
    end
  end
end
