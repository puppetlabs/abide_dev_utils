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
  allow(FileTest).to receive(:file?).with("#{Dir.pwd}/object_templates/class.erb").and_return(true)
  allow(File).to receive(:read).with("#{Dir.pwd}/object_templates/class.erb").and_return(test_erb)
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
  allow(FileTest).to receive(:file?).with("#{Dir.pwd}/custom_tmpl_dir/custom.erb").and_return(true)
end

def new_obj_cmap_stubs
  allow(Dir).to receive(:exist?).and_call_original
  allow(FileTest).to receive(:file?).and_call_original
  allow(File).to receive(:read).and_call_original
  allow(File).to receive(:open).and_call_original
  allow(File).to receive(:file?).and_call_original
  allow(Dir).to receive(:exist?).with('/test/tmpl_dir').and_return(true)
  allow(FileTest).to receive(:file?).with('/test/tmpl_dir/test.erb').and_return(true)
end

RSpec.describe 'AbideDevUtils::Ppt::NewObjectBuilder' do
  let(:new_obj_cls) do
    AbideDevUtils::Ppt::NewObjectBuilder.new(
      'class',
      'test::new::object::name'
    )
  end
  let(:new_obj_cust) do
    AbideDevUtils::Ppt::NewObjectBuilder.new(
      'test',
      'test::new::custom::name',
      opts: {
        tmpl_dir: 'custom_tmpl_dir',
        tmpl_name: 'custom.erb'
      }
    )
  end
  let(:new_obj_cmap) do
    AbideDevUtils::Ppt::NewObjectBuilder.new(
      'test',
      'test::new::custom::name',
      opts: {
        absolute_template_dir: true,
        tmpl_dir: '/test/tmpl_dir',
        type_path_map: {
          test: {
            path: 'manifests/custom_obj',
            extension: '.rb'
          }
        }
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

  it 'creates a builder object' do
    new_obj_cls_stubs(test_erb)
    expect(new_obj_cls).to exist
  end

  it 'creates a builder object of a custom type' do
    new_obj_cust_stubs
    expect(new_obj_cust).to exist
  end

  it 'creates a builder object of a custom type with map' do
    new_obj_cmap_stubs
    expect(new_obj_cmap).to exist
  end

  it 'has correct object path for class type' do
    new_obj_cls_stubs(test_erb)
    expect(new_obj_cls.obj_path).to eq "#{Dir.pwd}/manifests/new/object/name.pp"
  end

  it 'has correct object path for custom type' do
    new_obj_cust_stubs
    expect(new_obj_cust.obj_path).to eq "#{Dir.pwd}/manifests/new/custom/name.pp"
  end

  it 'has correct object path for custom type with map' do
    new_obj_cmap_stubs
    expect(new_obj_cmap.obj_path).to eq "#{Dir.pwd}/manifests/custom_obj/name.rb"
  end

  it 'correctly handles rendering a template' do
    new_obj_cls_stubs(test_erb)
    expect(new_obj_cls.render).to eq test_rendered_erb
  end

  it 'correctly handles building a template' do
    new_obj_cls_stubs(test_erb)
    expect(new_obj_cls.build).to eq "Created file #{Dir.pwd}/manifests/new/object/name.pp"
  end
end
