using System;
using Domain.InGame;

namespace Features.InGame
{
    public interface IInGameSoundSystem
    {
        void UpdateEmotionBGM(SidePanelDTO data);
        void SetLayerVolumes(float baseVol, float melodyVol, float ambientVol);
        float BaseVolume { get; }
        float MelodyVolume { get; }
        float AmbientVolume { get; }
    }

    public class InGameSoundSystem : IInGameSoundSystem
    {
        private readonly ISoundService m_soundService;
        private float m_baseVolume;
        private float m_melodyVolume;
        private float m_ambientVolume;

        public float BaseVolume
        {
            get
            {
                return m_baseVolume;
            }
        }

        public float MelodyVolume
        {
            get
            {
                return m_melodyVolume;
            }
        }

        public float AmbientVolume
        {
            get
            {
                return m_ambientVolume;
            }
        }

        public InGameSoundSystem(ISoundService soundService)
        {
            m_soundService = soundService;
            m_baseVolume = 1.0f;
            m_melodyVolume = 1.0f;
            m_ambientVolume = 1.0f;
        }

        public void UpdateEmotionBGM(SidePanelDTO data)
        {
            if (data == null)
            {
                return;
            }
            if (data.Sadness >= 5)
            {
                m_baseVolume = 1.0f;
                m_melodyVolume = 0.5f;
                m_ambientVolume = 0.2f;
            }
            else
            {
                m_baseVolume = 1.0f;
                m_melodyVolume = 1.0f;
                m_ambientVolume = 1.0f;
            }
            if (m_soundService != null)
            {
                m_soundService.SetVolume(m_baseVolume, m_melodyVolume);
            }
        }

        public void SetLayerVolumes(float baseVol, float melodyVol, float ambientVol)
        {
            m_baseVolume = baseVol;
            m_melodyVolume = melodyVol;
            m_ambientVolume = ambientVol;
            if (m_soundService != null)
            {
                m_soundService.SetVolume(m_baseVolume, m_melodyVolume);
            }
        }
    }
}
