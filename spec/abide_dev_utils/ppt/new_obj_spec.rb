# frozen_string_literal: true

require 'tempfile'
require 'abide_dev_utils'

def new_obj_cls_stubs(test_erb)
  allow(Dir).to receive(:exist?).and_call_original
  allow(FileTest).to receive(:file?).and_call_original
  allow(File).to receive(:read).and_call_original
  allow(File).to receive(:open).and_call_original
  allow(File).to receive(:file?).and_call_original
  allow(Dir).to receive(:exist?).with("#{Dir.pwd}/object_templates").and_return(true)
  allow(Dir).to receive(:entries).with("#{Dir.pwd}/object_templates").and_return(['test.erb'])
  allow(FileTest).to receive(:file?).with("#{Dir.pwd}/object_templates/test.erb").and_return(true)
  allow(File).to receive(:read).with("#{Dir.pwd}/object_templates/test.erb").and_return(test_erb)
  allow(File).to receive(:open).with("#{Dir.pwd}/manifests/new/object/name.pp", 'w').and_return(true)
  allow(File).to receive(:file?).with("#{Dir.pwd}/manifests/new/object/name.pp").and_return(true)
end

def new_obj_cust_stubs
  allow(Dir).to receive(:exist?).and_call_original
  allow(FileTest).to receive(:file?).and_call_original
  allow(File).to receive(:read).and_call_original
  allow(File).to receive(:open).and_call_original
  allow(File).to receive(:file?).and_call_original
  allow(Dir).to receive(:exist?).with("#{Dir.pwd}/custom_tmpl_dir").and_return(true)
  allow(Dir).to receive(:entries).with("#{Dir.pwd}/custom_tmpl_dir").and_return(['custom.erb'])
  allow(FileTest).to receive(:file?).with("#{Dir.pwd}/custom_tmpl_dir/custom.erb").and_return(true)
end

RSpec.describe 'AbideDevUtils::Ppt::NewObjectBuilder' do
  let(:new_obj_cls) do
    AbideDevUtils::Ppt::NewObjectBuilder.new(
      'test',
      'test::new::object::name',
      opts: {
        force: true
      }
    )
  end
  let(:new_obj_cust) do
    AbideDevUtils::Ppt::NewObjectBuilder.new(
      'test2',
      'test::new::custom::name',
      opts: {
        tmpl_dir: 'custom_tmpl_dir',
        tmpl_name: 'custom.erb',
        force: true
      }
    )
  end

  let(:test_erb) do
    <<~ERB
      # @api private
      class <%= @obj_name %> (
        Boolean $enforced = true,
        Hash $config = {},
      ) {
        if $enforced {
          warning('Class not implemented yet')
        }
      }

    ERB
  end

  let(:test_rendered_erb) do
    <<~ERB
      # @api private
      class test::new::object::name (
        Boolean $enforced = true,
        Hash $config = {},
      ) {
        if $enforced {
          warning('Class not implemented yet')
        }
      }

    ERB
  end

  let(:test_erb_file) do
    Tempfile.new('erb')
  end

  let(:test_tmpl_data) do
    {
      path: "#{Dir.pwd}/object_templates/d-test.rb.erb",
      fname: 'd-test.rb.erb',
      ext: '.rb',
      pfx: 'd-',
      spec_base: 'defines',
      obj_name: 'test.rb',
      spec_name: 'test_spec.rb',
      spec_path: "#{Dir.pwd}/spec/defines/new/object/test_spec.rb"
    }
  end

  it 'creates a builder object' do
    new_obj_cls_stubs(test_erb)
    expect(new_obj_cls).to exist
  end

  it 'creates a builder object of a custom type' do
    new_obj_cust_stubs
    expect(new_obj_cust).to exist
  end

  it 'has correct object path for class type' do
    new_obj_cls_stubs(test_erb)
    expect(new_obj_cls.obj_path).to eq "#{Dir.pwd}/manifests/new/object/name.pp"
  end

  it 'has correct object path for custom type' do
    new_obj_cust_stubs
    expect(new_obj_cust.obj_path).to eq "#{Dir.pwd}/manifests/new/custom/name.pp"
  end

  it 'correctly finds template file' do
    new_obj_cls_stubs(test_erb)
    allow(Dir).to receive(:entries).with("#{Dir.pwd}/object_templates").and_return(['test.pp.erb'])
    expect(new_obj_cls.send(:templates)).to eq ["#{Dir.pwd}/object_templates/test.pp.erb"]
  end

  it 'correctly filters invalid template file' do
    new_obj_cls_stubs(test_erb)
    allow(Dir).to receive(:entries).with("#{Dir.pwd}/object_templates").and_return(['test.pp.erb', 'test.pp'])
    expect(new_obj_cls.send(:templates)).to eq ["#{Dir.pwd}/object_templates/test.pp.erb"]
  end

  it 'correctly parses template data' do
    new_obj_cls_stubs(test_erb)
    allow(Dir).to receive(:entries).with("#{Dir.pwd}/object_templates").and_return(['d-test.rb.erb'])
    expect(new_obj_cls.send(:template_data, 'test')).to eq test_tmpl_data
  end

  it 'correctly handles rendering a template' do
    new_obj_cls_stubs(test_erb)
    expect(new_obj_cls.send(:render, "#{Dir.pwd}/object_templates/test.erb")).to eq test_rendered_erb
  end

  # TODO: Need to implement something like FakeFS to test this properly
  # it 'correctly handles building a template' do
  #   new_obj_cls_stubs(test_erb)
  #   expect(new_obj_cls.build).not_to raise_error
  # end
end
