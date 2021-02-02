# frozen_string_literal: true

require 'abide_dev_utils'

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
        root_relative: false,
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

  it 'creates a builder object' do
    expect(new_obj_cls).to exist
  end

  it 'creates a builder object of a custom type' do
    expect(new_obj_cust).to exist
  end

  it 'creates a builder object of a custom type with map' do
    expect(new_obj_cmap).to exist
  end

  it 'has correct object path for class type' do
    expect(new_obj_cls.obj_path).to eq "#{Dir.pwd}/manifests/new/object/name.pp"
  end

  it 'has correct object path for custom type' do
    expect(new_obj_cust.obj_path).to eq "#{Dir.pwd}/manifests/new/custom/name.pp"
  end

  it 'has correct object path for custom type with map' do
    expect(new_obj_cmap.obj_path).to eq "#{Dir.pwd}/manifests/custom_obj/name.rb"
  end

  it 'finds template by default name' do
    allow(FileTest).to receive(:file?).with("#{Dir.pwd}/object_templates/name.erb").and_return(true)
    expect(new_obj_cls.template?).to eq true
  end

  it 'finds custom template name in custom template dir' do
    allow(FileTest).to receive(:file?).with("#{Dir.pwd}/custom_tmpl_dir/custom.erb").and_return(true)
    expect(new_obj_cust.template?).to eq true
  end

  it 'finds template in non-root relative custom template dir' do
    allow(FileTest).to receive(:file?).with('/test/tmpl_dir/name.erb').and_return(true)
  end

  it 'correctly handles rendering a template' do
    allow(FileTest).to receive(:file?).with("#{Dir.pwd}/object_templates/name.erb").and_return(true)
    allow(File).to receive(:read).with("#{Dir.pwd}/object_templates/name.erb").and_return(test_erb)
    expect(new_obj_cls.render).to eq test_rendered_erb
  end

  it 'correctly handles building a template' do
    allow(FileTest).to receive(:file?).with("#{Dir.pwd}/object_templates/name.erb").and_return(true)
    allow(File).to receive(:read).with("#{Dir.pwd}/object_templates/name.erb").and_return(test_erb)
    allow(File).to receive(:open).with("#{Dir.pwd}/manifests/new/object/name.pp", 'w').and_return(true)
    expect(new_obj_cls.build).to eq true
  end
end
