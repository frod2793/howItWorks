using System;

namespace Features.Settings
{
    public class SettingsViewModel : ISettingsViewModel
    {
        private readonly ISoundService m_soundService;

        private float m_originalMasterVolume;
        private float m_originalBGMVolume;
        private float m_originalSFXVolume;
        private float m_originalVoiceVolume;
        private bool m_originalMuteOnFocusLost;

        public event Action OnStateChanged;
        public event Action OnCloseRequested;

        public SettingsViewModel(ISoundService soundService)
        {
            m_soundService = soundService;
            BackupSettings();
        }

        private void BackupSettings()
        {
            if (m_soundService != null)
            {
                m_originalMasterVolume = m_soundService.MasterVolume;
                m_originalBGMVolume = m_soundService.BGMVolume;
                m_originalSFXVolume = m_soundService.SFXVolume;
                m_originalVoiceVolume = m_soundService.VoiceVolume;
                m_originalMuteOnFocusLost = m_soundService.MuteOnFocusLost;
            }
        }

        public float MasterVolume
        {
            get
            {
                return m_soundService != null ? m_soundService.MasterVolume : 0.8f;
            }
            set
            {
                if (m_soundService != null)
                {
                    m_soundService.SetMasterVolume(value);
                    if (OnStateChanged != null)
                    {
                        OnStateChanged.Invoke();
                    }
                }
            }
        }

        public float BGMVolume
        {
            get
            {
                return m_soundService != null ? m_soundService.BGMVolume : 0.7f;
            }
            set
            {
                if (m_soundService != null)
                {
                    m_soundService.SetBGMVolume(value);
                    if (OnStateChanged != null)
                    {
                        OnStateChanged.Invoke();
                    }
                }
            }
        }

        public float SFXVolume
        {
            get
            {
                return m_soundService != null ? m_soundService.SFXVolume : 0.85f;
            }
            set
            {
                if (m_soundService != null)
                {
                    m_soundService.SetSFXVolume(value);
                    if (OnStateChanged != null)
                    {
                        OnStateChanged.Invoke();
                    }
                }
            }
        }

        public float VoiceVolume
        {
            get
            {
                return m_soundService != null ? m_soundService.VoiceVolume : 0.75f;
            }
            set
            {
                if (m_soundService != null)
                {
                    m_soundService.SetVoiceVolume(value);
                    if (OnStateChanged != null)
                    {
                        OnStateChanged.Invoke();
                    }
                }
            }
        }

        public bool MuteOnFocusLost
        {
            get
            {
                return m_soundService != null ? m_soundService.MuteOnFocusLost : true;
            }
            set
            {
                if (m_soundService != null)
                {
                    m_soundService.SetMuteOnFocusLost(value);
                    if (OnStateChanged != null)
                    {
                        OnStateChanged.Invoke();
                    }
                }
            }
        }

        public void ApplySettings()
        {
            if (m_soundService != null)
            {
                m_soundService.SaveSettings();
                BackupSettings();
            }
            Close();
        }

        public void CancelSettings()
        {
            if (m_soundService != null)
            {
                m_soundService.SetMasterVolume(m_originalMasterVolume);
                m_soundService.SetBGMVolume(m_originalBGMVolume);
                m_soundService.SetSFXVolume(m_originalSFXVolume);
                m_soundService.SetVoiceVolume(m_originalVoiceVolume);
                m_soundService.SetMuteOnFocusLost(m_originalMuteOnFocusLost);
            }
            Close();
        }

        public void ResetToDefault()
        {
            MasterVolume = 0.8f;
            BGMVolume = 0.7f;
            SFXVolume = 0.85f;
            VoiceVolume = 0.75f;
            MuteOnFocusLost = true;
        }

        public void Close()
        {
            if (OnCloseRequested != null)
            {
                OnCloseRequested.Invoke();
            }
        }
    }
}
