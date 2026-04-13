#!/usr/bin/env ruby

# 🚀 Dchat - Script PERMANENTE para desbloquear o Chatwoot Enterprise
# Execute com: wget -qO- https://raw.githubusercontent.com/PhyBruno/Chatwoot-Unlock/2341f8208b97f1dca8c16c4c1ee2c7130a506529/unlock_permanent.rb | bundle exec rails runner -

require 'fileutils'

puts "🚀 === Dchat - Desbloqueio PERMANENTE do Chatwoot Enterprise ==="
puts ""

# SQL para criar trigger permanente
sql_trigger = <<-SQL
CREATE OR REPLACE FUNCTION force_enterprise_installation_configs()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.name = 'INSTALLATION_PRICING_PLAN' THEN
        NEW.serialized_value = to_jsonb('--- !ruby/hash:ActiveSupport::HashWithIndifferentAccess\nvalue: enterprise\n'::text);
        NEW.locked = true;
    END IF;

    IF NEW.name = 'INSTALLATION_PRICING_PLAN_QUANTITY' THEN
        NEW.serialized_value = to_jsonb('--- !ruby/hash:ActiveSupport::HashWithIndifferentAccess\nvalue: 9999999\n'::text);
        NEW.locked = true;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_force_enterprise_configs ON installation_configs;

CREATE TRIGGER trg_force_enterprise_configs
BEFORE INSERT OR UPDATE ON installation_configs
FOR EACH ROW
EXECUTE FUNCTION force_enterprise_installation_configs();
SQL

begin
  puts "📊 Aplicando trigger permanente no PostgreSQL..."
  ActiveRecord::Base.connection.execute(sql_trigger)
  puts "✅ Trigger criado com sucesso!"
  puts "   • Função: force_enterprise_installation_configs()"
  puts "   • Trigger: trg_force_enterprise_configs"
  puts ""
rescue => e
  puts "❌ Erro ao criar trigger: #{e.message}"
  puts ""
end

# Atualiza registros diretamente via SQL
begin
  puts "💾 Atualizando configurações no banco de dados..."

  conn = ActiveRecord::Base.connection

  plan_yaml     = "--- !ruby/hash:ActiveSupport::HashWithIndifferentAccess\nvalue: enterprise\n"
  quantity_yaml = "--- !ruby/hash:ActiveSupport::HashWithIndifferentAccess\nvalue: 9999999\n"

  plan_yaml_escaped     = conn.quote(plan_yaml)
  quantity_yaml_escaped = conn.quote(quantity_yaml)

  conn.execute(<<-SQL)
    INSERT INTO installation_configs (name, serialized_value, locked, created_at, updated_at)
    VALUES (
      'INSTALLATION_PRICING_PLAN',
      to_jsonb(#{plan_yaml_escaped}::text),
      true,
      NOW(),
      NOW()
    )
    ON CONFLICT (name) DO UPDATE
      SET serialized_value = to_jsonb(#{plan_yaml_escaped}::text),
          locked = true,
          updated_at = NOW();
  SQL
  puts "✅ Plano enterprise configurado e bloqueado"

  conn.execute(<<-SQL)
    INSERT INTO installation_configs (name, serialized_value, locked, created_at, updated_at)
    VALUES (
      'INSTALLATION_PRICING_PLAN_QUANTITY',
      to_jsonb(#{quantity_yaml_escaped}::text),
      true,
      NOW(),
      NOW()
    )
    ON CONFLICT (name) DO UPDATE
      SET serialized_value = to_jsonb(#{quantity_yaml_escaped}::text),
          locked = true,
          updated_at = NOW();
  SQL
  puts "✅ Quantidade de usuários configurada e bloqueada (9.999.999)"
  puts ""

rescue => e
  puts "❌ Erro nas configurações do banco: #{e.message}"
  puts ""
end

# Limpa cache Redis
begin
  if defined?(Redis::Alfred)
    Redis::Alfred.delete(Redis::Alfred::CHATWOOT_INSTALLATION_CONFIG_RESET_WARNING)
    puts '✅ Flag de alerta premium removida do Redis'
  end
rescue => e
  puts "⚠️  Erro ao limpar Redis: #{e.message}"
end

# Atualiza fallbacks e URL do hub em lib/chatwoot_hub.rb
begin
  possible_paths = [
    '/app/lib/chatwoot_hub.rb',
    '/chatwoot/lib/chatwoot_hub.rb',
    File.join(Rails.root, 'lib', 'chatwoot_hub.rb'),
    './lib/chatwoot_hub.rb'
  ]

  hub_file = possible_paths.find { |path| File.exist?(path) }

  if hub_file
    puts "📁 Arquivo encontrado: #{hub_file}"

    backup_file = "#{hub_file}.backup.#{Time.now.strftime('%Y%m%d_%H%M%S')}"
    FileUtils.cp(hub_file, backup_file)
    puts "💾 Backup: #{backup_file}"

    content  = File.read(hub_file)
    original = content.dup

    # Altera URL do hub para endereço inválido (impede validação remota)
    content.gsub!(
      /DEFAULT_BASE_URL\s*=\s*['"]https:\/\/hub\.[^'"]+['"]/,
      "DEFAULT_BASE_URL = 'https://hub.invalid'"
    )

    # Atualiza fallback do plano
    content.gsub!(
      /(InstallationConfig\.find_by\(name:\s*['"]INSTALLATION_PRICING_PLAN['"]\)&?\.value\s*\|\|\s*)['"]community['"]/,
      "\\1'enterprise'"
    )

    # Atualiza fallback da quantidade
    content.gsub!(
      /(InstallationConfig\.find_by\(name:\s*['"]INSTALLATION_PRICING_PLAN_QUANTITY['"]\)&?\.value\s*\|\|\s*)0/,
      "\\19999999"
    )

    if content != original
      File.write(hub_file, content)
      puts "✅ URL do hub bloqueada (hub.invalid)"
      puts "✅ Fallbacks atualizados em #{hub_file}"
    else
      puts "ℹ️  Arquivo já estava atualizado"
    end
    puts ""
  end

rescue => e
  puts "⚠️  Erro ao atualizar arquivo: #{e.message}"
  puts ""
end

# Verifica configurações finais
begin
  puts "🔍 Verificando configurações aplicadas:"

  configs = InstallationConfig.where(name: ['INSTALLATION_PRICING_PLAN', 'INSTALLATION_PRICING_PLAN_QUANTITY'])
  configs.each do |config|
    puts "   • #{config.name}: #{config.value} (locked: #{config.locked || false})"
  end

  trigger_check = ActiveRecord::Base.connection.execute(
    "SELECT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_force_enterprise_configs') as exists"
  ).first

  if trigger_check && trigger_check['exists']
    puts "   • Trigger PostgreSQL: ✅ ATIVO"
  else
    puts "   • Trigger PostgreSQL: ⚠️  Não detectado"
  end

  # Verifica URL do hub no arquivo
  if hub_file && File.exist?(hub_file)
    hub_url_line = File.readlines(hub_file).find { |l| l.include?('DEFAULT_BASE_URL') }
    puts "   • Hub URL: #{hub_url_line&.strip || 'não encontrada'}"
  end

rescue => e
  puts "⚠️  Erro ao verificar: #{e.message}"
end

puts ""
puts "🎉 === Desbloqueio PERMANENTE concluído ==="
puts ""
puts "🔒 PROTEÇÃO ATIVA:"
puts "   • Trigger PostgreSQL monitora e força valores enterprise"
puts "   • Qualquer tentativa de alterar será revertida automaticamente"
puts "   • Configurações marcadas como 'locked'"
puts "   • Comunicação com hub.chatwoot.com bloqueada"
puts ""
puts "🔄 Reinicie o container para aplicar todas as mudanças"
puts "🌟 Dchat - Educational Project"
puts ""
