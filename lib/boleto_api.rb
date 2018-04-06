require 'brcobranca'
require 'grape'

module BoletoApi

  def self.get_boleto(bank, values)

    clazz = Object.const_get("Brcobranca::Boleto::#{bank.camelize}")
    date_fields = %w[data_documento data_vencimento data_processamento]
    date_fields.each do |date_field|
      values[date_field] = Date.parse(values[date_field]) if values[date_field]
    end
    clazz.new(values)
  end

  def self.get_pagamento(values)
    date_fields = %w[data_vencimento data_emissao data_desconto data_segundo_desconto data_multa]
    date_fields.each do |date_field|
      values[date_field] = Date.parse(values[date_field]) if values[date_field]
    end
    values['data_vencimento'] ||= Date.current
  
  end

  class Server < Grape::API
    version 'v1', using: :header, vendor: 'Kionux'
    format :json
    prefix :api

    resource :boleto do

      desc 'Valida dados do boleto'
      
      params do
        requires :bank, type: String, desc: 'Banco'
        requires :data, type: String, desc: 'Dados do boleto em JSON em forma de string'
      end
      get :validate do
        values = JSON.parse(params[:data])
        boleto = BoletoApi.get_boleto(params[:bank], values)
        if boleto.valid?
          true
        else
          error!(boleto.errors.messages, 400)
        end
      end

      desc 'Retorna um boleto, em forma de imagem ou pdf'
      
      params do
        requires :bank, type: String, desc: 'Banco'
        requires :type, type: String, desc: 'Type: pdf|jpg|png|tif'
        requires :data, type: String, desc: 'Dados do boleto em json em forma de string'
      end
      get do
        
        values = JSON.parse(params[:data])
      
        
        boleto = BoletoApi.get_boleto(params[:bank], values)
        
        
        params[:bank]
        if boleto.valid?
          content_type "application/#{params[:type]}"
          header['Content-Disposition'] = "attachment; filename=MSBANK-#{params[:bank]}.#{params[:type]}"
          env['api.format'] = :binary
          boleto.send("to_#{params[:type]}".to_sym)
        else
          error!(boleto.errors.messages, 400)
        end
      end

      desc 'Retorna um ou mais boletos, em formato de pdf ou imagem'
      
      params do
        requires :type, type: String, desc: 'Type: pdf|jpg|png|tif'
        requires :data, type: File, desc: 'json of the list of boletos, including the "bank" key'
      end
      post :multi do
        values = JSON.parse(params[:data][:tempfile].read())
      	boletos = []
        errors = []
        values.each do |boleto_values|
          bank = "Brcobranca::Boleto::#{boleto_values.delete('bank').camelize}"
          boleto = BoletoApi.get_boleto(bank, boleto_values)
          if boleto.valid?
            boletos << boleto
          else
            errors << boleto.errors.messages
          end
        end
        if errors.empty?
          content_type "application/#{params[:type]}"
          header['Content-Disposition'] = "attachment; filename=boletos-#{params[:bank]}.#{params[:type]}"
          env['api.format'] = :binary
          Brcobranca::Boleto::Base.lote(boletos, formato: params[:type].to_sym)
        else
          error!(errors, 400)
        end
      end
    end


    RETORNO_FIELDS = [:codigo_registro,:codigo_ocorrencia,:data_ocorrencia,:agencia_com_dv,:agencia_sem_dv,:cedente_com_dv,:convenio,:nosso_numero,:codigo_ocorrencia,:data_ocorrencia,:tipo_cobranca,:tipo_cobranca_anterior,:natureza_recebimento,:carteira_variacao,:desconto,:iof,:carteira,:comando,:data_liquidacao,:data_vencimento,:valor_titulo,:banco_recebedor,:agencia_recebedora_com_dv,:especie_documento,:data_ocorrencia,:data_credito,:valor_tarifa,:outras_despesas,:juros_desconto,:iof_desconto,:valor_abatimento,:desconto_concedito,:valor_recebido,:juros_mora,:outros_recebimento,:abatimento_nao_aproveitado,:valor_lancamento,:indicativo_lancamento,:indicador_valor,:valor_ajuste,:sequencial,:arquivo,:outros_recebimento,:motivo_ocorrencia,:documento_numero]
    
    resource :retorno do
      
      params do
        requires :bank, type: String, desc: 'Bank'
        requires :type, type: String, desc: 'Type: cnab400|cnab240'
        requires :data, type: File, desc: 'txt of the retorno file'
      end
      post do
        data = params[:data][:tempfile]
        clazz = Object.const_get("Brcobranca::Retorno::#{params[:type].camelize}::#{params[:bank].camelize}")
        pagamentos = clazz.load_lines(data)
        pagamentos.map! do |p|
          Hash[RETORNO_FIELDS.map{|sym| [sym, p.send(sym)]}]
        end
        JSON.generate(pagamentos)
      end
    end
  end
end
