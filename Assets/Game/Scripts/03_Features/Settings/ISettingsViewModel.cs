using System;

namespace Features.Settings
{
    public interface ISettingsViewModel
    {
        float MasterVolume { get; set; }
        float BGMVolume { get; set; }
        float SFXVolume { get; set; }
        float VoiceVolume { get; set; }
        bool MuteOnFocusLost { get; set; }

        event Action OnStateChanged;
        event Action OnCloseRequested;

        void ApplySettings();
        void CancelSettings();
        void ResetToDefault();
        void Close();
        void PlayClickSound();
        void PlayMenuOpenSound();
        void PlayMenuCloseSound();
    }
}
