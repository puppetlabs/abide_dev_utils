# frozen_string_literal: true

require 'happymapper'

module AbideDevUtils
  module XCCDF
    class Status
      include HappyMapper
      tag 'status'
      attribute :date, String
      content :status, String
    end

    class Title
      include HappyMapper
      tag 'title'
      attribute :lang, String, namespace: 'xml'
      content :title, String
    end

    class XHtmlSpan
      include HappyMapper
      tag 'span'
      namespace 'xhtml'
      attribute :class, String
      content :span, String
    end

    class XHtmlCode
      include HappyMapper
      tag 'code'
      namespace 'xhtml'
      attribute :class, String
      content :code, String
    end

    class XHtmlUL
      include HappyMapper
      tag 'ul'
      namespace 'xhtml'
      has_many :lis, String, tag: 'li', namespace: 'xhtml'
    end

    class XHtmlP
      include HappyMapper
      tag 'p'
      namespace 'xhtml'
      has_many :strongs, String, tag: 'strong', namespace: 'xhtml'
      has_many :spans, XHtmlSpan, tag: 'span', namespace: 'xhtml'
      has_many :codes, XHtmlCode, tag: 'code', namespace: 'xhtml'
      # has_many :ps, XHtmlP, tag: 'p', namespace: 'xhtml'
      has_many :uls, XHtmlUL, tag: 'ul', namespace: 'xhtml'
      content :p, String
    end

    class XHtmlDiv
      include HappyMapper
      tag 'div'
      namespace 'xhtml'
      element :p, XHtmlP, tag: 'p', namespace: 'xhtml'
    end

    class Description
      include HappyMapper
      tag 'description'
      attribute :lang, String, namespace: 'xml'
      has_many :ps, XHtmlP, namespace: 'xhtml', tag: 'p'
      has_many :uls, XHtmlUL, namespace: 'xhtml', tag: 'ul'
    end

    class Notice
      include HappyMapper
      tag 'notice'
      attribute :id, String
      attribute :lang, String, namespace: 'xml'
      content :notice, String, namespace: 'xccdf'
    end

    class Select
      include HappyMapper
      tag 'select'
      attribute :idref, String
      attribute :selected, String
    end

    class Profile
      include HappyMapper
      tag 'Profile'
      attribute :id, String
      element :title, Title, namespace: 'xccdf'
      element :description, Description, namespace: 'xccdf'
      has_many :select, Select, namespace: 'xccdf'
    end

    class Value
      include HappyMapper
      tag 'Value'
      attribute :id, String
      attribute :operator, String
      attribute :type, String
      element :title, String
      element :description, String
      element :value, String
    end

    class Rationale
      include HappyMapper
      tag 'rationale'
      attribute :lang, String, namespace: 'xml'
      element :p, XHtmlP, namespace: 'xhtml'
    end

    class Ident
      include HappyMapper
      tag 'ident'
      attribute :control_uri, String, namespace: 'cc7', tag: 'controlURI'
      attribute :system, String
      content :ident, String
    end

    class Fixtext
      include HappyMapper
      tag 'fixtext'
      attribute :lang, String, namespace: 'xml'
      element :div, XHtmlDiv, namespace: 'xhtml'
    end

    class CheckImport
      include HappyMapper
      tag 'check-import'
      attribute :import_name, String, tag: 'import-name'
    end

    class CheckExport
      include HappyMapper
      tag 'check-export'
      attribute :export_name, String, tag: 'export-name'
      attribute :value_id, String, tag: 'value-id'
    end

    class Check
      include HappyMapper
      tag 'check'
      attribute :system, String
      element :check_content_ref, String, attributes: { href: String, name: String }, tag: 'check-content-ref'
      element :check_import, CheckImport, tag: 'check-import'
      element :check_export, CheckExport, tag: 'check-export'
    end

    class ComplexCheck
      include HappyMapper
      tag 'complex-check'
      attribute :operator, String
      has_many :complex_checks, ComplexCheck, tag: 'complex-check'
      has_many :checks, Check, tag: 'check'
    end

    class Rule
      include HappyMapper
      tag 'Rule'
      attribute :id, String
      attribute :role, String
      attribute :selected, String
      attribute :weight, String
      element :title, Title, namespace: 'xccdf'
      element :descriptiong, Description, namespace: 'xccdf'
      element :rationale, Rationale, namespace: 'xccdf'
      element :ident, Ident, namespace: 'xccdf'
      element :fixtext, Fixtext, namespace: 'xccdf'
      element :complex_check, ComplexCheck, namespace: 'xccdf', tag: 'complex-check'
    end

    class Group
      include HappyMapper
      tag 'Group'
      attribute :id, String
      element :title, Title, namespace: 'xccdf'
      element :description, Description, namespace: 'xccdf'
      # has_many :groups, Group, tag: 'Group', namespace: 'xccdf'
      has_many :rules, Rule, tag: 'Rule', namespace: 'xccdf'
    end

    class DSTransforms
      include HappyMapper
      tag 'Transforms'
      namespace 'ds'
      has_many :transform, String, attributes: { Algorithm: String }, tag: 'Transform'
    end

    class DSReference
      include HappyMapper
      tag 'Reference'
      namespace 'ds'
      attribute :uri, String, tag: 'URI'
      element :transforms, DSTransforms, tag: 'Transforms', namespace: 'ds'
      element :digest_method, String, attributes: { Algorithm: String }, tag: 'DigestMethod', namespace: 'ds'
      element :digest_value, String, tag: 'DigestValue', namespace: 'ds'
    end

    class DSSignedInfo
      include HappyMapper
      tag 'SignedInfo'
      namespace 'ds'
      element :cannonicalization_method, String, attributes: { Algorithm: String }, tag: 'CannonicalizationMethod', namespace: 'ds'
      element :signature_method, String, attributes: { Algorithm: String }, tag: 'SignatureMethod', namespace: 'ds'
      element :reference, DSReference, tag: 'Reference', namespace: 'ds'
    end

    class DSX509Data
      include HappyMapper
      tag 'X509Data'
      namespace 'ds'
      element :x509_certificate, String, tag: 'X509Certificate', namespace: 'ds'
    end

    class DSRSAKeyValue
      include HappyMapper
      tag 'RSAKeyValue'
      namespace 'ds'
      element :modulus, String, tag: 'Modulus', namespace: 'ds'
      element :exponent, String, tag: 'Exponent', namespace: 'ds'
    end

    class DSKeyValue
      include HappyMapper
      tag 'KeyValue'
      namespace 'ds'
      element :rsa_key_value, DSRSAKeyValue, tag: 'RSAKeyValue', namespace: 'ds'
    end

    class DSKeyInfo
      include HappyMapper
      tag 'KeyInfo'
      namespace 'ds'
      element :x509_data, DSX509Data, tag: 'X509Data', namespace: 'ds'
      element :key_value, DSKeyValue, tag: 'KeyValue', namespace: 'ds'
    end

    class DSSignature
      include HappyMapper
      tag 'Signature'
      namespace 'ds'
      element :signed_info, DSSignedInfo, tag: 'SignedInfo'
      element :signature_value, String, tag: 'SignatureValue'
      element :key_info, DSKeyInfo, tag: 'KeyInfo'
    end

    class Signature
      include HappyMapper
      tag 'signature'
      element :signature, DSSignature, tag: 'Signature', namespace: 'ds'
    end

    class Benchmark
      include HappyMapper

      register_namespace 'xccdf', 'http://checklists.nist.gov/xccdf/1.2'
      register_namespace 'ae', 'http://benchmarks.cisecurity.org/ae/0.5'
      register_namespace 'cc6', 'http://cisecurity.org/20-cc/v6.1'
      register_namespace 'cc7', 'http://cisecurity.org/20-cc/v7.0'
      register_namespace 'ciscf', 'https://benchmarks.cisecurity.org/ciscf/1.0'
      register_namespace 'notes', 'http://benchmarks.cisecurity.org/notes'
      register_namespace 'xhtml', 'http://www.w3.org/1999/xhtml'
      register_namespace 'xsi', 'http://www.w3.org/2001/XMLSchema-instance'
      register_namespace 'ds', 'http://www.w3.org/2000/09/xmldsig#'

      tag 'Benchmark'
      namespace 'xccdf'
      attribute :xmlns, String, tag: 'xmlns'
      attribute :id, String, tag: 'id'
      attribute :style, String, tag: 'style'
      attribute :schema_location, String, tag: 'schemaLocation', namespace: 'xsi'
      element :status, Status, tag: 'status', namespace: 'xccdf'
      element :title, Title, tag: 'title', namespace: 'xccdf'
      element :description, Description, tag: 'description', namespace: 'xccdf'
      element :notice, Notice, tag: 'notice', namespace: 'xccdf'
      element :platform, String, attributes: { idref: String }, xpath: '.', tag: 'platform', namespace: 'xccdf'
      element :version, String, tag: 'version', namespace: 'xccdf'
      has_many :profiles, Profile, tag: 'Profile', namespace: 'xccdf'
      has_many :values, Value, tag: 'Value'
      has_many :groups, Group, tag: 'Group', namespace: 'xccdf'
      element :signature, Signature, tag: 'signature', namespace: 'xccdf'
    end
  end
end
