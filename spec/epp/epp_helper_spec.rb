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
    end
  end
end
