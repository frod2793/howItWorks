using UnityEngine;

#region 내부 로직
/// <summary>
/// [설명]: 게임 전역의 사운드(BGM, SFX) 재생을 담당하는 서비스 인터페이스입니다.
/// </summary>
public interface ISoundService
{
    /// <summary>
    /// [설명]: 배경 음악을 재생합니다. 기존 음악이 있으면 페이드 아웃 후 교체됩니다.
    /// </summary>
    /// <param name="key">오디오 클립 키값</param>
    /// <param name="fadeDuration">페이드 시간</param>
    /// <param name="loop">반복 여부</param>
    void PlayBGM(string key, float fadeDuration = 0.5f, bool loop = true);

    /// <summary>
    /// [설명]: 현재 재생 중인 배경 음악을 정지합니다.
    /// </summary>
    /// <param name="fadeDuration">페이드 시간</param>
    void StopBGM(float fadeDuration = 0.5f);

    /// <summary>
    /// [설명]: 효과음을 1회 재생합니다.
    /// </summary>
    void PlaySFX(string key, float volumeScale = 1.0f);

    /// <summary>
    /// [설명]: 루핑되는 효과음을 재생합니다 (예: 타이핑 소리).
    /// </summary>
    void PlayLoopSFX(string key, float volumeScale = 1.0f);

    /// <summary>
    /// [설명]: 루핑 중인 특정 효과음을 정지합니다.
    /// </summary>
    void StopLoopSFX();

    /// <summary>
    /// [설명]: 전체 볼륨 설정을 변경합니다.
    /// </summary>
    void SetVolume(float bgmVolume, float sfxVolume);
}
#endregion
