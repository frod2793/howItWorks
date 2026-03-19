using UnityEngine;
using System.Collections.Generic;
using DG.Tweening;
using VContainer;

#region 내부 로직
/// <summary>
/// [설명]: 실제 오디오 재생을 담당하는 Mono기반 사운드 서비스입니다.
/// </summary>
public class SoundService : MonoBehaviour, ISoundService
{
    #region 내부 필드
    private AudioSource m_bgmSource;
    private AudioSource m_sfxSource;
    private AudioSource m_loopSfxSource;
    private SoundDataProvider m_dataProvider;
    
    private float m_bgmMasterVolume = 1.0f;
    private float m_sfxMasterVolume = 1.0f;
    #endregion

    [Inject]
    public void Construct(SoundDataProvider dataProvider)
    {
        m_dataProvider = dataProvider;
    }

    private void Awake()
    {
        // 1. BGM 소스 초기화
        m_bgmSource = gameObject.AddComponent<AudioSource>();
        m_bgmSource.playOnAwake = false;
        m_bgmSource.loop = true;

        // 2. SFX 소스 초기화
        m_sfxSource = gameObject.AddComponent<AudioSource>();
        m_sfxSource.playOnAwake = false;

        // 3. 루핑 SFX 소스 초기화 (타이핑 등 전용)
        m_loopSfxSource = gameObject.AddComponent<AudioSource>();
        m_loopSfxSource.playOnAwake = false;
        m_loopSfxSource.loop = true;
    }

    #region ISoundService 구현
    public void PlayBGM(string key, float fadeDuration = 0.5f, bool loop = true)
    {
        var clip = m_dataProvider?.GetClip(key);
        if (clip == null) return;

        // 이미 같은 곡이 재생 중이면 무시
        if (m_bgmSource.clip == clip && m_bgmSource.isPlaying) return;

        if (m_bgmSource.isPlaying && fadeDuration > 0)
        {
            // 교차 페이드 (단순화: 볼륨 0으로 내리고 교체 후 다시 올림)
            m_bgmSource.DOFade(0, fadeDuration).OnComplete(() =>
            {
                m_bgmSource.Stop();
                m_bgmSource.clip = clip;
                m_bgmSource.loop = loop;
                m_bgmSource.Play();
                m_bgmSource.DOFade(m_bgmMasterVolume, fadeDuration);
            });
        }
        else
        {
            m_bgmSource.Stop();
            m_bgmSource.clip = clip;
            m_bgmSource.loop = loop;
            m_bgmSource.volume = m_bgmMasterVolume;
            m_bgmSource.Play();
        }
    }

    public void StopBGM(float fadeDuration = 0.5f)
    {
        if (fadeDuration > 0)
        {
            m_bgmSource.DOFade(0, fadeDuration).OnComplete(() => m_bgmSource.Stop());
        }
        else
        {
            m_bgmSource.Stop();
        }
    }

    public void PlaySFX(string key, float volumeScale = 1.0f)
    {
        var clip = m_dataProvider?.GetClip(key);
        if (clip != null)
        {
            m_sfxSource.PlayOneShot(clip, volumeScale * m_sfxMasterVolume);
        }
    }

    public void PlayLoopSFX(string key, float volumeScale = 1.0f)
    {
        var clip = m_dataProvider?.GetClip(key);
        if (clip != null)
        {
            m_loopSfxSource.clip = clip;
            m_loopSfxSource.volume = volumeScale * m_sfxMasterVolume;
            if (!m_loopSfxSource.isPlaying) m_loopSfxSource.Play();
        }
    }

    public void StopLoopSFX()
    {
        if (m_loopSfxSource != null) m_loopSfxSource.Stop();
    }

    public void SetVolume(float bgmVolume, float sfxVolume)
    {
        m_bgmMasterVolume = Mathf.Clamp01(bgmVolume);
        m_sfxMasterVolume = Mathf.Clamp01(sfxVolume);
        
        if (m_bgmSource != null) m_bgmSource.volume = m_bgmMasterVolume;
    }
    #endregion
}
#endregion
