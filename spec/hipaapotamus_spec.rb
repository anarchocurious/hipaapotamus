require 'spec_helper'

describe Hipaapotamus do
  it 'has a version number' do
    expect(Hipaapotamus::VERSION).not_to be nil
  end

  describe '.current_accountability_context' do
    it 'delegates to Hipaapotamus::AccountabilityContext.current' do
      expect(Hipaapotamus::AccountabilityContext).to receive(:current)

      Hipaapotamus.current_accountability_context
    end
  end

  describe '.current_agent' do
    it 'delegates to .current_accountability_context.agent' do
      expect(Hipaapotamus).to receive(:current_accountability_context)

      Hipaapotamus.current_agent
    end
  end

  describe '.with_accountability' do
    let(:agent) { User.create! }
    let(:defended) { Hipaapotamus.without_accountability { MedicalSecret.create! } }
    let(:defended_id) { defended.id }
    let(:very_defended) { Hipaapotamus.without_accountability { PatientSecret.create! } }
    let(:very_defended_id) { very_defended.id }

    it 'evaluates a block in an AccountabilityContext with the provided agent' do
      Hipaapotamus.with_accountability(agent) do
        expect(Hipaapotamus::AccountabilityContext.current.agent).to eq agent
      end
    end

    it 'uses the policy scope' do
      patient_secret = Hipaapotamus.without_accountability do
        PatientSecret.create!(serial_number: 'out of scope')
      end

      Hipaapotamus.with_accountability(agent) do
        expect(PatientSecret.policy_scoped.find_by(id: patient_secret.id)).to be_nil
      end
    end

    it 'filters attributes during mass assignment with ActionController::Parameters' do
      params = ActionController::Parameters.new(patient_secret: { serial_number: 'woot' })

      Hipaapotamus.without_accountability do
        allow_any_instance_of(PatientSecretPolicy).to receive(:permitted_attributes).and_return([:serial_number])

        very_defended.assign_attributes(params.require(:patient_secret).permit(:serial_number) )
        expect(very_defended.serial_number).to eq 'woot'

        very_defended.serial_number = 'toot'

        allow_any_instance_of(PatientSecretPolicy).to receive(:permitted_attributes).and_return([])
        very_defended.assign_attributes(params.require(:patient_secret).permit(:serial_number) )
        expect(very_defended.serial_number).to eq 'toot'
      end
    end

    context 'within a transaction' do
      it 'records all the accesses that occur within the accountability context' do
        defended
        agent

        ActiveRecord::Base.transaction do
          Hipaapotamus.with_accountability(agent) do
            MedicalSecret.find_by!(id: defended_id)
          end

          raise ActiveRecord::Rollback
        end

        action = Hipaapotamus::Action.last

        expect(action.action_type).to eq 'access'
        expect(action.agent).to eq agent

        Hipaapotamus.without_accountability do
          expect(action.defended).to eq defended
        end
      end
    end

    context 'within a nested transaction' do
      it 'records all the accesses that occur within the accountability context' do
        defended
        agent

        ActiveRecord::Base.transaction do
          ActiveRecord::Base.transaction(requires_new: true) do
            Hipaapotamus.with_accountability(agent) do
              MedicalSecret.find_by!(id: defended_id)
            end

            raise ActiveRecord::Rollback
          end
        end

        action = Hipaapotamus::Action.last

        expect(action.action_type).to eq 'access'
        expect(action.agent).to eq agent

        Hipaapotamus.without_accountability do
          expect(action.defended).to eq defended
        end
      end
    end

    context 'for authorized agents' do
      it 'records all the accesses that occur within the accountability context' do
        Hipaapotamus.with_accountability(agent) do
          MedicalSecret.find_by!(id: defended_id)
        end

        action = Hipaapotamus::Action.last

        expect(action.action_type).to eq 'access'
        expect(action.agent).to eq agent

        Hipaapotamus.without_accountability do
          expect(action.defended).to eq defended
        end
      end

      it 'records all the creations that occur within the accountability context' do
        medical_secret = Hipaapotamus.with_accountability(agent) do
          MedicalSecret.create!
        end

        action = Hipaapotamus::Action.last

        expect(action.action_type).to eq 'creation'
        expect(action.agent).to eq agent

        Hipaapotamus.without_accountability do
          expect(action.defended).to eq medical_secret
        end
      end

      it 'records all the modifications that occur within the accountability context' do
        Hipaapotamus.with_accountability(agent) do
          defended.update_attributes!({})
        end

        action = Hipaapotamus::Action.last

        expect(action.action_type).to eq 'modification'
        expect(action.agent).to eq agent

        Hipaapotamus.without_accountability do
          expect(action.defended).to eq defended
        end
      end

      it 'records all the destructions that occur within the accountability context' do
        Hipaapotamus.with_accountability(agent) do
          defended.destroy!
        end

        action = Hipaapotamus::Action.last

        expect(action.action_type).to eq 'destruction'
        expect(action.agent).to eq agent

        Hipaapotamus.without_accountability do
          expect(action.defended).to eq defended
        end
      end
    end

    context 'for unauthorized agents' do
      it 'records all failed accesses that occur within the accountability context' do
        very_defended #Ensures that record is created in case transaction rollsback

        expect do
          Hipaapotamus.with_accountability(agent) do
            PatientSecret.find_by!(id: very_defended_id)
          end
        end.to raise_error Hipaapotamus::AccountabilityError

        action = Hipaapotamus::Action.last

        expect(action.action_type).to eq 'attempted_access'
        expect(action.agent).to eq agent

        Hipaapotamus.without_accountability do
          expect(action.defended).to eq very_defended
        end
      end

      it 'records all failed creations that occur within the accountability context' do
        patient_secret = nil

        expect do
          Hipaapotamus.with_accountability(agent) do
            patient_secret = PatientSecret.new(serial_number: SecureRandom.hex(64))

            patient_secret.save!
          end
        end.to raise_error Hipaapotamus::AccountabilityError

        action = Hipaapotamus::Action.last

        expect(action.action_type).to eq 'attempted_creation'
        expect(action.agent).to eq agent

        Hipaapotamus.without_accountability do
          expect(action.defended.serial_number).to eq patient_secret.serial_number
        end
      end

      it 'records all failed modifications that occur within the accountability context' do
        very_defended #Ensures that record is created in case transaction rollsback

        expect do
          Hipaapotamus.with_accountability(agent) do
            very_defended.update_attributes!({})
          end
        end.to raise_error Hipaapotamus::AccountabilityError

        action = Hipaapotamus::Action.last

        expect(action.action_type).to eq 'attempted_modification'
        expect(action.agent).to eq agent

        Hipaapotamus.without_accountability do
          expect(action.defended).to eq very_defended
        end
      end

      it 'records all failed destructions that occur within the accountability context' do
        very_defended #Ensures that record is created in case transaction rollsback

        expect do
          Hipaapotamus.with_accountability(agent) do
            very_defended.destroy!
          end
        end.to raise_error Hipaapotamus::AccountabilityError

        action = Hipaapotamus::Action.last

        expect(action.action_type).to eq 'attempted_destruction'
        expect(action.agent).to eq agent

        Hipaapotamus.without_accountability do
          expect(action.defended).to eq very_defended
        end
      end
    end

    # TODO: Figure out what the hell is up with transactions vis a vis sqlite
    context 'when the outermost transaction rollsback' do
      it 'still records access' do
        defended #Ensures that record is created in case transaction rollsback

        Hipaapotamus.with_accountability(agent) do
          ActiveRecord::Base.transaction do
            MedicalSecret.find_by!(id: defended_id)

            raise ActiveRecord::Rollback
          end
        end

        action = Hipaapotamus::Action.last

        expect(action.action_type).to eq 'access'
        expect(action.agent).to eq agent

        Hipaapotamus.without_accountability do
          expect(action.defended).to eq defended
        end
      end

      it 'does not record creation' do
        medical_secret = nil

        Hipaapotamus.with_accountability(agent) do
          ActiveRecord::Base.transaction(requires_new: true) do
            medical_secret = MedicalSecret.create!

            raise ActiveRecord::Rollback
          end
        end

        expect(Hipaapotamus::Action.with_defended(medical_secret).creation.count).to eq 0
      end

      it 'does not record modification' do
        medical_secret = defended

        Hipaapotamus.with_accountability(agent) do
          ActiveRecord::Base.transaction(requires_new: true) do
            medical_secret.update_attributes!({})

            raise ActiveRecord::Rollback
          end
        end

        expect(Hipaapotamus::Action.with_defended(medical_secret).modification.count).to eq 0
      end

      it 'does not record destruction' do
        medical_secret = defended

        Hipaapotamus.with_accountability(agent) do
          ActiveRecord::Base.transaction(requires_new: true) do
            medical_secret.destroy!

            raise ActiveRecord::Rollback
          end
        end

        expect(Hipaapotamus::Action.with_defended(medical_secret).destruction.count).to eq 0
      end
    end
  end

  describe '.without_accountability' do
    let(:anonymous_agent) { Hipaapotamus::AnonymousAgent.instance }

    it 'evaluates a block in an AccountabilityContext with the anonymous agent' do
      expect(Hipaapotamus).to receive(:with_accountability).with(anonymous_agent)

      Hipaapotamus.without_accountability do
        # tested in .with_accountability
      end
    end
  end

end
