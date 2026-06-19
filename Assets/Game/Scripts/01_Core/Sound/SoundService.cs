using UnityEngine;
using System.Collections.Generic;
using DG.Tweening;
using VContainer;

public class SoundService : MonoBehaviour, ISoundService
{
    private AudioSource m_bgmSource;
    private AudioSource m_sfxSource;
    private AudioSource m_loopSfxSource;
    private AudioSource m_voiceSource;
    private SoundDataProvider m_dataProvider;
    
    private float m_masterVolume = 0.8f;
    private float m_bgmVolume = 0.7f;
    private float m_sfxVolume = 0.85f;
    private float m_voiceVolume = 0.75f;
    private bool m_muteOnFocusLost = true;

    [Inject]
    public void Construct(SoundDataProvider dataProvider)
    {
        m_dataProvider = dataProvider;
    }

    private void Awake()
    {
        m_bgmSource = gameObject.AddComponent<AudioSource>();
        m_bgmSource.playOnAwake = false;
        m_bgmSource.loop = true;

        m_sfxSource = gameObject.AddComponent<AudioSource>();
        m_sfxSource.playOnAwake = false;

        m_loopSfxSource = gameObject.AddComponent<AudioSource>();
        m_loopSfxSource.playOnAwake = false;
        m_loopSfxSource.loop = true;

        m_voiceSource = gameObject.AddComponent<AudioSource>();
        m_voiceSource.playOnAwake = false;

        LoadSettings();
    }

    public void PlayBGM(string key, float fadeDuration = 0.5f, bool loop = true)
    {
        AudioClip clip = null;
        if (m_dataProvider != null)
        {
            clip = m_dataProvider.GetClip(key);
        }

        if (clip == null)
        {
            return;
        }

        if (m_bgmSource.clip == clip && m_bgmSource.isPlaying)
        {
            return;
        }

        if (m_bgmSource.isPlaying && fadeDuration > 0)
        {
            m_bgmSource.DOFade(0, fadeDuration).OnComplete(() =>
            {
                m_bgmSource.Stop();
                m_bgmSource.clip = clip;
                m_bgmSource.loop = loop;
                m_bgmSource.Play();
                m_bgmSource.DOFade(m_bgmVolume * m_masterVolume, fadeDuration);
            });
        }
        else
        {
            m_bgmSource.Stop();
            m_bgmSource.clip = clip;
            m_bgmSource.loop = loop;
            m_bgmSource.volume = m_bgmVolume * m_masterVolume;
            m_bgmSource.Play();
        }
    }

    public void StopBGM(float fadeDuration = 0.5f)
    {
        if (fadeDuration > 0)
        {
            m_bgmSource.DOFade(0, fadeDuration).OnComplete(() =>
            {
                m_bgmSource.Stop();
            });
        }
        else
        {
            m_bgmSource.Stop();
        }
    }

    public void PlaySFX(string key, float volumeScale = 1.0f)
    {
        AudioClip clip = null;
        if (m_dataProvider != null)
        {
            clip = m_dataProvider.GetClip(key);
        }

        if (clip != null)
        {
            m_sfxSource.PlayOneShot(clip, volumeScale * m_sfxVolume * m_masterVolume);
        }
    }

    public void PlayLoopSFX(string key, float volumeScale = 1.0f)
    {
        AudioClip clip = null;
        if (m_dataProvider != null)
        {
            clip = m_dataProvider.GetClip(key);
        }

        if (clip != null)
        {
            m_loopSfxSource.clip = clip;
            m_loopSfxSource.volume = volumeScale * m_sfxVolume * m_masterVolume;
            if (!m_loopSfxSource.isPlaying)
            {
                m_loopSfxSource.Play();
            }
        }
    }

    public void StopLoopSFX()
    {
        if (m_loopSfxSource != null)
        {
            m_loopSfxSource.Stop();
        }
    }

    public void SetVolume(float bgmVolume, float sfxVolume)
    {
        SetBGMVolume(bgmVolume);
        SetSFXVolume(sfxVolume);
    }

    public float MasterVolume
    {
        get
        {
            return m_masterVolume;
        }
    }

    public float BGMVolume
    {
        get
        {
            return m_bgmVolume;
        }
    }

    public float SFXVolume
    {
        get
        {
            return m_sfxVolume;
        }
    }

    public float VoiceVolume
    {
        get
        {
            return m_voiceVolume;
        }
    }

    public bool MuteOnFocusLost
    {
        get
        {
            return m_muteOnFocusLost;
        }
    }

    public void SetMasterVolume(float volume)
    {
        m_masterVolume = Mathf.Clamp01(volume);
        UpdateAudioSourcesVolume();
    }

    public void SetBGMVolume(float volume)
    {
        m_bgmVolume = Mathf.Clamp01(volume);
        UpdateAudioSourcesVolume();
    }

    public void SetSFXVolume(float volume)
    {
        m_sfxVolume = Mathf.Clamp01(volume);
        UpdateAudioSourcesVolume();
    }

    public void SetVoiceVolume(float volume)
    {
        m_voiceVolume = Mathf.Clamp01(volume);
        UpdateAudioSourcesVolume();
    }

    public void SetMuteOnFocusLost(bool mute)
    {
        m_muteOnFocusLost = mute;
    }

    public void LoadSettings()
    {
        m_masterVolume = PlayerPrefs.GetFloat("Settings_MasterVolume", 0.8f);
        m_bgmVolume = PlayerPrefs.GetFloat("Settings_BGMVolume", 0.7f);
        m_sfxVolume = PlayerPrefs.GetFloat("Settings_SFXVolume", 0.85f);
        m_voiceVolume = PlayerPrefs.GetFloat("Settings_VoiceVolume", 0.75f);
        m_muteOnFocusLost = PlayerPrefs.GetInt("Settings_MuteOnFocusLost", 1) == 1;

        UpdateAudioSourcesVolume();
    }

    public void SaveSettings()
    {
        PlayerPrefs.SetFloat("Settings_MasterVolume", m_masterVolume);
        PlayerPrefs.SetFloat("Settings_BGMVolume", m_bgmVolume);
        PlayerPrefs.SetFloat("Settings_SFXVolume", m_sfxVolume);
        PlayerPrefs.SetFloat("Settings_VoiceVolume", m_voiceVolume);
        PlayerPrefs.SetInt("Settings_MuteOnFocusLost", m_muteOnFocusLost ? 1 : 0);
        PlayerPrefs.Save();
    }

    private void UpdateAudioSourcesVolume()
    {
        if (m_bgmSource != null)
        {
            m_bgmSource.volume = m_bgmVolume * m_masterVolume;
        }
        if (m_sfxSource != null)
        {
            m_sfxSource.volume = m_sfxVolume * m_masterVolume;
        }
        if (m_loopSfxSource != null)
        {
            m_loopSfxSource.volume = m_sfxVolume * m_masterVolume;
        }
        if (m_voiceSource != null)
        {
            m_voiceSource.volume = m_voiceVolume * m_masterVolume;
        }
    }

    private void OnApplicationFocus(bool hasFocus)
    {
        if (m_muteOnFocusLost)
        {
            AudioListener.pause = !hasFocus;
        }
    }
}
