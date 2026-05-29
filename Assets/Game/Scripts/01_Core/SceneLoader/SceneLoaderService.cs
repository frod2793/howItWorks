using UnityEngine;
using EasyTransition;
using System.Linq;

#region 내부 로직
/// <summary>
/// [설명]: Easy Transition 패키지를 활용한 씬 전환 서비스 구현체입니다.
/// </summary>
public class SceneLoaderService : ISceneLoader
{
    private const string DEFAULT_TRANSITION_PATH = "Transitions/Fade";
    private TransitionSettings m_defaultSettings;

    public SceneLoaderService()
    {
        m_defaultSettings = Resources.Load<TransitionSettings>(DEFAULT_TRANSITION_PATH);
        
        if (m_defaultSettings == null)
        {
            Debug.LogWarning("[SceneLoaderService] 기본 설정 로드 실패: Fade");
        }
    }

    public void LoadScene(string sceneName, float startDelay = 0f)
    {
        if (m_defaultSettings == null)
        {
            m_defaultSettings = Resources.Load<TransitionSettings>(DEFAULT_TRANSITION_PATH);
        }

        var manager = TransitionManager.Instance();
        if (manager == null)
        {
            Debug.LogError("[SceneLoaderService] TransitionManager 인스턴스 없음");
            return;
        }

        if (m_defaultSettings == null)
        {
            Debug.LogError($"[SceneLoaderService] 에셋 로드 실패: {DEFAULT_TRANSITION_PATH}");
            return;
        }

        manager.Transition(sceneName, m_defaultSettings, startDelay);
    }

    public void LoadSceneWithData<T>(string sceneName, T data, float startDelay = 0f)
    {
        LoadScene(sceneName, startDelay);
    }
}
#endregion
