require 'rails_helper'

describe 'EPP Helper', epp: true do
  context 'in context of Domain' do
    it 'generates valid create xml' do
      expected = Nokogiri::XML('<?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <epp xmlns="urn:ietf:params:xml:ns:epp-1.0">
          <command>
            <create>
              <domain:create
               xmlns:domain="urn:ietf:params:xml:ns:domain-1.0">
                <domain:name>example.ee</domain:name>
                <domain:period unit="y">1</domain:period>
                <domain:ns>
                  <domain:hostObj>ns1.example.net</domain:hostObj>
                  <domain:hostObj>ns2.example.net</domain:hostObj>
                </domain:ns>
                <domain:registrant>jd1234</domain:registrant>
                <domain:contact type="admin">sh8013</domain:contact>
                <domain:contact type="tech">sh8013</domain:contact>
                <domain:contact type="tech">sh801333</domain:contact>
                <domain:authInfo>
                  <domain:pw>2fooBAR</domain:pw>
                </domain:authInfo>
              </domain:create>
            </create>
            <clTRID>ABC-12345</clTRID>
          </command>
        </epp>
      ').to_s.squish

      generated = Nokogiri::XML(domain_create_xml).to_s.squish
      expect(generated).to eq(expected)

      ###

      expected = Nokogiri::XML('<?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <epp xmlns="urn:ietf:params:xml:ns:epp-1.0">
          <command>
            <create>
              <domain:create
               xmlns:domain="urn:ietf:params:xml:ns:domain-1.0">
                <domain:name>one.ee</domain:name>
                <domain:period unit="d">345</domain:period>
                <domain:ns>
                  <domain:hostObj>ns1.test.net</domain:hostObj>
                  <domain:hostObj>ns2.test.net</domain:hostObj>
                </domain:ns>
                <domain:registrant>32fsdaf</domain:registrant>
                <domain:contact type="admin">2323rafaf</domain:contact>
                <domain:contact type="tech">3dgxx</domain:contact>
                <domain:contact type="tech">345xxv</domain:contact>
                <domain:authInfo>
                  <domain:pw>sdgdgd4esfsa</domain:pw>
                </domain:authInfo>
              </domain:create>
            </create>
            <clTRID>ABC-12345</clTRID>
          </command>
        </epp>
      ').to_s.squish

      xml = domain_create_xml(
        name: 'one.ee',
        period_value: '345',
        period_unit: 'd',
        nameservers: [{ hostObj: 'ns1.test.net' }, { hostObj: 'ns2.test.net' }],
        registrant: '32fsdaf',
        contacts: [
          { contact_value: '2323rafaf', contact_type: 'admin' },
          { contact_value: '3dgxx', contact_type: 'tech' },
          { contact_value: '345xxv', contact_type: 'tech' }
        ],
        pw: 'sdgdgd4esfsa'
      )

      generated = Nokogiri::XML(xml).to_s.squish
      expect(generated).to eq(expected)

      ###

      expected = Nokogiri::XML('<?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <epp xmlns="urn:ietf:params:xml:ns:epp-1.0">
          <command>
            <create>
              <domain:create
               xmlns:domain="urn:ietf:params:xml:ns:domain-1.0">
                <domain:name>one.ee</domain:name>
              </domain:create>
            </create>
            <clTRID>ABC-12345</clTRID>
          </command>
        </epp>
      ').to_s.squish

      xml = domain_create_xml(
        name: 'one.ee',
        period: false,
        nameservers: [],
        registrant: false,
        contacts: [],
        authInfo: false
      )

      generated = Nokogiri::XML(xml).to_s.squish
      expect(generated).to eq(expected)
    end

    it 'generates valid info xml' do
      expected = Nokogiri::XML('<?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <epp xmlns="urn:ietf:params:xml:ns:epp-1.0">
          <command>
            <info>
              <domain:info
               xmlns:domain="urn:ietf:params:xml:ns:domain-1.0">
                <domain:name hosts="all">example.ee</domain:name>
                <domain:authInfo>
                  <domain:pw>2fooBAR</domain:pw>
                </domain:authInfo>
              </domain:info>
            </info>
            <clTRID>ABC-12345</clTRID>
          </command>
        </epp>
      ').to_s.squish

      generated = Nokogiri::XML(domain_info_xml).to_s.squish
      expect(generated).to eq(expected)

      expected = Nokogiri::XML('<?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <epp xmlns="urn:ietf:params:xml:ns:epp-1.0">
          <command>
            <info>
              <domain:info
               xmlns:domain="urn:ietf:params:xml:ns:domain-1.0">
                <domain:name hosts="sub">one.ee</domain:name>
                <domain:authInfo>
                  <domain:pw>b3rafsla</domain:pw>
                </domain:authInfo>
              </domain:info>
            </info>
            <clTRID>ABC-12345</clTRID>
          </command>
        </epp>
      ').to_s.squish

      generated = Nokogiri::XML(domain_info_xml(name_value: 'one.ee', name_hosts: 'sub', pw: 'b3rafsla')).to_s.squish
      expect(generated).to eq(expected)
    end

    it 'generates valid check xml' do
      expected = Nokogiri::XML('<?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <epp xmlns="urn:ietf:params:xml:ns:epp-1.0">
          <command>
            <check>
              <domain:check
               xmlns:domain="urn:ietf:params:xml:ns:domain-1.0">
                <domain:name>example.ee</domain:name>
              </domain:check>
            </check>
            <clTRID>ABC-12345</clTRID>
          </command>
        </epp>
      ').to_s.squish

      generated = Nokogiri::XML(domain_check_xml).to_s.squish
      expect(generated).to eq(expected)

      expected = Nokogiri::XML('<?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <epp xmlns="urn:ietf:params:xml:ns:epp-1.0">
          <command>
            <check>
              <domain:check
               xmlns:domain="urn:ietf:params:xml:ns:domain-1.0">
                <domain:name>example.ee</domain:name>
                <domain:name>example2.ee</domain:name>
                <domain:name>example3.ee</domain:name>
              </domain:check>
            </check>
            <clTRID>ABC-12345</clTRID>
          </command>
        </epp>
      ').to_s.squish

      generated = Nokogiri::XML(domain_check_xml(names: ['example.ee', 'example2.ee', 'example3.ee'])).to_s.squish
      expect(generated).to eq(expected)
    end

    it 'generates valid renew xml' do
      expected = Nokogiri::XML('<?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <epp xmlns="urn:ietf:params:xml:ns:epp-1.0">
          <command>
            <renew>
              <domain:renew
               xmlns:domain="urn:ietf:params:xml:ns:domain-1.0">
                <domain:name>example.ee</domain:name>
                <domain:curExpDate>2014-08-07</domain:curExpDate>
                <domain:period unit="y">1</domain:period>
              </domain:renew>
            </renew>
            <clTRID>ABC-12345</clTRID>
          </command>
        </epp>
      ').to_s.squish

      generated = Nokogiri::XML(domain_renew_xml).to_s.squish
      expect(generated).to eq(expected)

      expected = Nokogiri::XML('<?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <epp xmlns="urn:ietf:params:xml:ns:epp-1.0">
          <command>
            <renew>
              <domain:renew
               xmlns:domain="urn:ietf:params:xml:ns:domain-1.0">
                <domain:name>one.ee</domain:name>
                <domain:curExpDate>2009-11-15</domain:curExpDate>
                <domain:period unit="d">365</domain:period>
              </domain:renew>
            </renew>
            <clTRID>ABC-12345</clTRID>
          </command>
        </epp>
      ').to_s.squish

      generated = Nokogiri::XML(domain_renew_xml(name: 'one.ee', curExpDate: '2009-11-15',
                                                 period_value: '365', period_unit: 'd')).to_s.squish
      expect(generated).to eq(expected)
    end

    it 'generates valid update xml' do
      expected = Nokogiri::XML('<?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <epp xmlns="urn:ietf:params:xml:ns:epp-1.0">
          <command>
            <update>
              <domain:update
               xmlns:domain="urn:ietf:params:xml:ns:domain-1.0">
                <domain:name>example.ee</domain:name>
                <domain:chg>
                  <domain:registrant>mak21</domain:registrant>
                  <domain:authInfo>
                    <domain:pw>2BARfoo</domain:pw>
                  </domain:authInfo>
                </domain:chg>
              </domain:update>
            </update>
            <clTRID>ABC-12345</clTRID>
          </command>
        </epp>
      ').to_s.squish

      generated = Nokogiri::XML(domain_update_xml).to_s.squish
      expect(generated).to eq(expected)

      expected = Nokogiri::XML('<?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <epp xmlns="urn:ietf:params:xml:ns:epp-1.0">
          <command>
            <update>
              <domain:update
               xmlns:domain="urn:ietf:params:xml:ns:domain-1.0">
                <domain:name>one.ee</domain:name>
                <domain:chg>
                  <domain:registrant>sh8013</domain:registrant>
                  <domain:authInfo>
                    <domain:pw>b3rafsla</domain:pw>
                  </domain:authInfo>
                </domain:chg>
              </domain:update>
            </update>
            <clTRID>ABC-12345</clTRID>
          </command>
        </epp>
      ').to_s.squish

      xml = domain_update_xml(name: 'one.ee', registrant: 'sh8013', pw: 'b3rafsla')

      generated = Nokogiri::XML(xml).to_s.squish
      expect(generated).to eq(expected)
    end

    it 'generates valid transfer xml' do
      expected = Nokogiri::XML('<?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <epp xmlns="urn:ietf:params:xml:ns:epp-1.0">
          <command>
            <transfer op="query">
              <domain:transfer
               xmlns:domain="urn:ietf:params:xml:ns:domain-1.0">
                <domain:name>example.ee</domain:name>
                <domain:authInfo>
                  <domain:pw roid="JD1234-REP">98oiewslkfkd</domain:pw>
                </domain:authInfo>
              </domain:transfer>
            </transfer>
            <clTRID>ABC-12345</clTRID>
          </command>
        </epp>
      ').to_s.squish

      generated = Nokogiri::XML(domain_transfer_xml).to_s.squish
      expect(generated).to eq(expected)

      expected = Nokogiri::XML('<?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <epp xmlns="urn:ietf:params:xml:ns:epp-1.0">
          <command>
            <transfer op="approve">
              <domain:transfer
               xmlns:domain="urn:ietf:params:xml:ns:domain-1.0">
                <domain:name>one.ee</domain:name>
                <domain:authInfo>
                  <domain:pw roid="askdf">test</domain:pw>
                </domain:authInfo>
              </domain:transfer>
            </transfer>
            <clTRID>ABC-12345</clTRID>
          </command>
        </epp>
      ').to_s.squish

      xml = domain_transfer_xml(name: 'one.ee', op: 'approve', pw: 'test', roid: 'askdf')

      generated = Nokogiri::XML(xml).to_s.squish
      expect(generated).to eq(expected)
    end

    it 'generates valid delete xml' do
      expected = Nokogiri::XML('<?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <epp xmlns="urn:ietf:params:xml:ns:epp-1.0">
          <command>
            <delete>
              <domain:delete
               xmlns:domain="urn:ietf:params:xml:ns:domain-1.0">
                <domain:name>example.ee</domain:name>
              </domain:delete>
            </delete>
            <clTRID>ABC-12345</clTRID>
          </command>
        </epp>
      ').to_s.squish

      generated = Nokogiri::XML(domain_delete_xml).to_s.squish
      expect(generated).to eq(expected)


      expected = Nokogiri::XML('<?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <epp xmlns="urn:ietf:params:xml:ns:epp-1.0">
          <command>
            <delete>
              <domain:delete
               xmlns:domain="urn:ietf:params:xml:ns:domain-1.0">
                <domain:name>one.ee</domain:name>
              </domain:delete>
            </delete>
            <clTRID>ABC-12345</clTRID>
          </command>
        </epp>
      ').to_s.squish

      generated = Nokogiri::XML(domain_delete_xml(name: 'one.ee')).to_s.squish
      expect(generated).to eq(expected)
    end
  end
end
