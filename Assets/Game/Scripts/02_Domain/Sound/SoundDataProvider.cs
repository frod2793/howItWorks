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

        // 1. BGM 폴더에서 검색 (하위 폴더 포함 가능성이 있으므로 경로 주의)
        // 실제 구조에 따라 "BGM/Title/titleSample02" 처럼 키를 넘겨야 할 수도 있습니다.
        var clip = Resources.Load<AudioClip>(BGM_PATH + key);
        
        // 2. SFX 폴더에서 검색
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
            Debug.LogWarning($"[SoundDataProvider] 오디오 클립을 찾을 수 없습니다: {key}");
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
