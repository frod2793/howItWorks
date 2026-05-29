using UnityEngine;
using System.Collections.Generic;

#region 내부 로직
/// <summary>
/// [설명]: 리소스 폴더의 오디오 클립을 로드하고 관리하는 데이터 제공자입니다.
/// </summary>
public class SoundDataProvider
{
    private const string BGM_PATH = "Sound/BGM/";
    private const string SFX_PATH = "Sound/SFX/";
    
    private readonly Dictionary<string, AudioClip> m_clipCache = new Dictionary<string, AudioClip>();

    /// <summary>
    /// [설명]: 키값을 통해 오디오 클립을 가져옵니다. (BGM 우선 검색)
    /// </summary>
    public AudioClip GetClip(string key)
    {
        if (m_clipCache.TryGetValue(key, out var cachedClip))
        {
            return cachedClip;
        }

        var clip = Resources.Load<AudioClip>(BGM_PATH + key);
        
        if (clip == null)
        {
            clip = Resources.Load<AudioClip>(SFX_PATH + key);
        }

        if (clip != null)
        {
            m_clipCache[key] = clip;
        }
        else
        {
            Debug.LogWarning($"[SoundDataProvider] 오디오 클립 로드 실패: {key}");
        }

        return clip;
    }

    /// <summary>
    /// [설명]: 메모리 절약을 위해 캐시를 비웁니다.
    /// </summary>
    public void ClearCache()
    {
        m_clipCache.Clear();
    }
}
#endregion
