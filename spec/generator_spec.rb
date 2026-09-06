# frozen_string_literal: true

RSpec.describe "deterministic Ruby projection" do
  it "generates a loadable service with the NovaPay transformations" do
    pipeline = SpecSupport.pipeline
    pipeline.validate_blueprint!
    Dir.mktmpdir("provider-compiler") do |directory|
      ProviderCompiler::DeterministicGenerator.new.generate(pipeline.blueprint, pipeline.manifest, directory)
      service_path = File.join(directory, "service.rb")
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-c", service_path)
      expect([stdout, stderr, status.success?]).to eq(["Syntax OK\n", "", true])

      load service_path
      service = Provider::NovapayService.new(api_key: "api-key", webhook_secret: "secret")
      operation = { amount: 15_000.0, currency: "RUB", id: "op_abc123", idempotency_key: "key-1", payout_requisite: { sbp: { phone: "79001234567", bank_code: "044525225" } } }
      request = service.build_create_request(operation)
      expect(request.dig("body", "amount")).to eq(1_500_000)
      expect(request.fetch("url")).to eq("https://api.sandbox.novapay.example/v1/payouts")
      expect(request.dig("headers", "Idempotency-Key")).to eq("key-1")
      decimal_request = service.build_create_request(operation.merge(amount: 1_500.50))
      expect(decimal_request.dig("body", "amount")).to eq(150_050)
      expect(service.build_create_request(operation.merge(amount: 1_500)).dig("body", "amount")).to eq(150_000)
      expect(service.check_conditions(operation.merge(amount: 1_500.50), "sbp")).to include("ok" => true)
      expect { service.build_create_request(operation.merge(amount: "not-a-money-value")) }.to raise_error(ArgumentError, /numeric/)
      expect(service.check_conditions(operation, "sbp")).to include("ok" => true)
      expect(service.check_conditions(operation.merge(payout_requisite: { sbp: { phone: "79001234567" } }), "sbp")).to include("ok" => false)
      expect(service.check_conditions(operation.merge(amount: 999.99), "sbp")).to include("ok" => false)
      execution_client = Class.new do
        def request(_method, _path, _headers, _body, _query)
          { "status" => 201, "body" => { "id" => "np_7f3a9b2c", "status" => "pending", "amount" => 1_500_000 } }
        end
      end.new
      executed = Provider::NovapayService.new(api_key: "api-key", client: execution_client).create_request(operation)
      expect(executed).to include("ok" => true, "provider_operation_id" => "np_7f3a9b2c", "amount" => 15_000.0, "result" => { "id" => "np_7f3a9b2c" })
      client = Class.new do
        def get(_path, _headers)
          { "status" => "completed", "amount" => 1_500_000 }
        end
      end.new
      status_result = Provider::NovapayService.new(api_key: "api-key", client: client).fetch_status(id: "np_7f3a9b2c")
      expect(status_result).to include("status" => "approved", "amount" => 15_000.0)
      decimal_client = Class.new do
        def get(_path, _headers)
          { "status" => "completed", "amount" => 150_050 }
        end
      end.new
      decimal_status = Provider::NovapayService.new(api_key: "api-key", client: decimal_client).fetch_status(id: "np_7f3a9b2c")
      expect(decimal_status).to include("status" => "approved", "amount" => 1_500.50)
      body = '{"event":"payout.completed","status":"completed","external_id":"op_abc123","payout_id":"np_7f3a9b2c"}'
      signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("SHA256"), "secret", body)
      expect(service.process_callback(raw_body: body, signature: signature)).to include("status" => "approved", "action" => "approve_operation", "terminal" => true)
      failed_body = '{"event":"payout.failed","status":"failed","external_id":"op_abc123","payout_id":"np_7f3a9b2c"}'
      failed_signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("SHA256"), "secret", failed_body)
      expect(service.process_callback(raw_body: failed_body, signature: failed_signature)).to include("status" => "rejected", "action" => "reject_operation", "terminal" => true)
      processing_body = '{"event":"payout.processing","status":"processing","external_id":"op_abc123","payout_id":"np_7f3a9b2c"}'
      processing_signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("SHA256"), "secret", processing_body)
      expect(service.process_callback(raw_body: processing_body, signature: processing_signature)).to include("status" => "in_progress", "action" => "none", "terminal" => false)
      cancelled_body = '{"event":"payout.cancelled","status":"cancelled","external_id":"op_abc123","payout_id":"np_7f3a9b2c"}'
      cancelled_signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("SHA256"), "secret", cancelled_body)
      expect(service.process_callback(raw_body: cancelled_body, signature: cancelled_signature)).to include("status" => "rejected", "action" => "reject_operation", "terminal" => true)
      expect(service.process_callback(raw_body: body, signature: "bad")).to include("ok" => false)
      expect(service.verify_webhook_signature(body, signature)).to be(true)
      expect(service.verify_webhook_signature(body, "bad")).to be(false)
      expect(service.provider_amount_to_host(150_000).to_f).to eq(1_500.0)
      expect(service.provider_amount_to_host(150_050).to_f).to eq(1_500.50)
      expect(service.provider_amount_to_host(1_500_000).to_f).to eq(15_000.0)
      expect(service.host_amount_to_provider(1_500.50)).to eq(150_050)
    end
  end

  it "fails safely when the profile does not declare terminal callback actions" do
    pipeline = SpecSupport.pipeline
    pipeline.validate_blueprint!
    blueprint = Marshal.load(Marshal.dump(pipeline.blueprint))
    blueprint["base_service_profile"]["callback_actions"] = {}
    Dir.mktmpdir("provider-callback-capability") do |directory|
      ProviderCompiler::DeterministicGenerator.new.generate(blueprint, pipeline.manifest, directory)
      Provider.send(:remove_const, :NovapayService) if Provider.const_defined?(:NovapayService, false)
      load File.join(directory, "service.rb")
      service = Provider::NovapayService.new(api_key: "api-key", webhook_secret: "secret")
      body = '{"event":"payout.completed","status":"completed","payout_id":"np_7f3a9b2c"}'
      signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("SHA256"), "secret", body)
      expect(service.process_callback(raw_body: body, signature: signature)).to include("ok" => false, "failure_code" => "unprocessable_entity", "error" => "callback action binding is unresolved")
    end
  end

  it "changes only adapter policy when always-send is selected" do
    pipeline = SpecSupport.pipeline(adapter_policy: "always")
    idempotency = pipeline.blueprint.fetch("idempotency")

    expect(idempotency.fetch("spec_required")).to be(false)
    expect(idempotency.dig("adapter_policy", "send_header")).to eq("always")
  end

  it "reuses an adapter-generated idempotency key for the same operation" do
    pipeline = SpecSupport.pipeline(adapter_policy: "always")
    pipeline.validate_blueprint!
    Dir.mktmpdir("provider-idempotency") do |directory|
      ProviderCompiler::DeterministicGenerator.new.generate(pipeline.blueprint, pipeline.manifest, directory)
      Provider.send(:remove_const, :NovapayService) if Provider.const_defined?(:NovapayService, false)
      load File.join(directory, "service.rb")
      service = Provider::NovapayService.new(api_key: "api-key")
      operation = { amount: 15_000.0, currency: "RUB", id: "op-retry", payout_requisite: { sbp: { phone: "79001234567", bank_code: "044525225" } } }
      first = service.build_create_request(operation)
      second = service.build_create_request(operation)
      expect(first.dig("headers", "Idempotency-Key")).to eq(second.dig("headers", "Idempotency-Key"))
      expect(first.dig("headers", "Idempotency-Key")).not_to be_nil
    end
  end

  it "produces byte-stable outputs for identical inputs" do
    pipeline = SpecSupport.pipeline
    pipeline.validate_blueprint!
    Dir.mktmpdir("provider-determinism") do |directory|
      first_dir = File.join(directory, "first")
      second_dir = File.join(directory, "second")
      generator = ProviderCompiler::DeterministicGenerator.new
      generator.generate(pipeline.blueprint, pipeline.manifest, first_dir, examples: pipeline.defaults.examples)
      generator.generate(pipeline.blueprint, pipeline.manifest, second_dir, examples: pipeline.defaults.examples)
      %w[provider_blueprint.json review_manifest.json service.rb fixtures.json INTEGRATION.md contract_smoke.rb].each do |name|
        expect(File.binread(File.join(first_dir, name))).to eq(File.binread(File.join(second_dir, name)))
      end
    end
  end
end
