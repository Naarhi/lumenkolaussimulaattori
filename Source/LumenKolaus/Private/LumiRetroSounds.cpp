#include "LumiRetroSounds.h"

#include "Sound/SoundWaveProcedural.h"

namespace
{
	constexpr int32 SampleRate = 22050;

	struct FSynth
	{
		TArray<int16> Samples;
		FRandomStream Random{ 1337 };

		/** Neliöaalto, jonka taajuus liukuu StartHz -> EndHz. Lisätään olemassa olevan päälle. */
		void Square(float StartSeconds, float Seconds, float StartHz, float EndHz, float Volume, float Duty = 0.5f)
		{
			const int32 First = FMath::RoundToInt(StartSeconds * SampleRate);
			const int32 Count = FMath::RoundToInt(Seconds * SampleRate);
			EnsureLength(First + Count);
			float Phase = 0.f;
			for (int32 I = 0; I < Count; ++I)
			{
				const float T = static_cast<float>(I) / Count;
				Phase = FMath::Fractional(Phase + FMath::Lerp(StartHz, EndHz, T) / SampleRate);
				const float Wave = Phase < Duty ? 1.f : -1.f;
				Mix(First + I, Wave * Volume * Envelope(T));
			}
		}

		/** Alipäästösuodatettu kohina (lumen pöllähdys). */
		void Noise(float StartSeconds, float Seconds, float Smoothing, float Volume)
		{
			const int32 First = FMath::RoundToInt(StartSeconds * SampleRate);
			const int32 Count = FMath::RoundToInt(Seconds * SampleRate);
			EnsureLength(First + Count);
			float Filtered = 0.f;
			for (int32 I = 0; I < Count; ++I)
			{
				const float T = static_cast<float>(I) / Count;
				Filtered += (Random.FRandRange(-1.f, 1.f) - Filtered) * Smoothing;
				Mix(First + I, Filtered * Volume * Envelope(T) * 2.f);
			}
		}

		/** Nopea isku alkuun ja lineaarinen hiipuminen, kuten vanhoissa äänipiireissä. */
		static float Envelope(float T)
		{
			const float Attack = FMath::Clamp(T / 0.02f, 0.f, 1.f);
			return Attack * (1.f - T);
		}

		void EnsureLength(int32 Length)
		{
			if (Samples.Num() < Length)
			{
				Samples.SetNumZeroed(Length);
			}
		}

		void Mix(int32 Index, float Value)
		{
			Samples[Index] = static_cast<int16>(FMath::Clamp(Samples[Index] + Value * 32767.f, -32767.f, 32767.f));
		}
	};

	void Compose(FSynth& Synth, ELumiRetroSound Sound)
	{
		switch (Sound)
		{
		case ELumiRetroSound::Scoop:
			Synth.Noise(0.f, 0.16f, 0.25f, 0.5f);
			Synth.Square(0.f, 0.06f, 180.f, 90.f, 0.25f);
			break;

		case ELumiRetroSound::Throw:
			Synth.Square(0.f, 0.18f, 520.f, 160.f, 0.2f, 0.25f);
			Synth.Noise(0.12f, 0.22f, 0.15f, 0.45f);
			break;

		case ELumiRetroSound::LevelUp:
		{
			// Nouseva arpeggio ja pitkä loppusointu, OSRS:n level up -fanfaarin henkeen.
			const float Notes[] = { 523.25f, 659.25f, 783.99f, 1046.5f };
			for (int32 Index = 0; Index < UE_ARRAY_COUNT(Notes); ++Index)
			{
				Synth.Square(Index * 0.12f, 0.16f, Notes[Index], Notes[Index], 0.22f, 0.5f);
			}
			Synth.Square(0.48f, 0.7f, 1046.5f, 1046.5f, 0.18f, 0.5f);
			Synth.Square(0.48f, 0.7f, 783.99f, 783.99f, 0.14f, 0.25f);
			Synth.Square(0.48f, 0.7f, 523.25f, 523.25f, 0.12f, 0.5f);
			break;
		}

		case ELumiRetroSound::Announcement:
			Synth.Square(0.f, 0.15f, 880.f, 880.f, 0.2f, 0.5f);
			Synth.Square(0.15f, 0.3f, 659.25f, 659.25f, 0.2f, 0.5f);
			break;
		}
	}
}

USoundBase* LumiRetroSounds::Create(UObject* Outer, ELumiRetroSound Sound)
{
	FSynth Synth;
	Compose(Synth, Sound);

	USoundWaveProcedural* Wave = NewObject<USoundWaveProcedural>(Outer);
	Wave->SetSampleRate(SampleRate);
	Wave->NumChannels = 1;
	Wave->Duration = static_cast<float>(Synth.Samples.Num()) / SampleRate;
	Wave->SoundGroup = SOUNDGROUP_Default;
	Wave->bLooping = false;
	Wave->QueueAudio(reinterpret_cast<const uint8*>(Synth.Samples.GetData()), Synth.Samples.Num() * sizeof(int16));
	return Wave;
}
