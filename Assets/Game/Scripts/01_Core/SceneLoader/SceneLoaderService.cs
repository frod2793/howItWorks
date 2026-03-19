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
        // 기본 페이드 트랜지션 설정 로드
        m_defaultSettings = Resources.Load<TransitionSettings>(DEFAULT_TRANSITION_PATH);
        
        if (m_defaultSettings == null)
        {
            Debug.LogWarning("[SceneLoaderService] 기본 트랜지션 설정을 찾을 수 없습니다. Resources/Transitions/Fade 확인 필요.");
        }
    }

    public void LoadScene(string sceneName, float startDelay = 0f)
    {
        // 최신 설정 재로드 시도 (싱글톤 인스턴스 생성이 파일 복사보다 빨랐을 경우 대비)
        if (m_defaultSettings == null)
        {
            m_defaultSettings = Resources.Load<TransitionSettings>(DEFAULT_TRANSITION_PATH);
        }

        var manager = TransitionManager.Instance();
        if (manager == null)
        {
            Debug.LogError("[SceneLoaderService] TransitionManager 인스턴스를 찾을 수 없습니다. 씬에 TransitionManager가 있는지 확인하세요.");
            return;
        }

        if (m_defaultSettings == null)
        {
            Debug.LogError($"[SceneLoaderService] '{DEFAULT_TRANSITION_PATH}' 에셋을 로드할 수 없습니다. Resources 폴더를 확인하세요.");
            return;
        }

        manager.Transition(sceneName, m_defaultSettings, startDelay);
    }

    public void LoadSceneWithData<T>(string sceneName, T data, float startDelay = 0f)
    {
        // TODO: 전달받은 데이터를 다음 씬의 Initializer에 주입하는 로직 추가 예정
        // 현재는 일반 씬 전환과 동일하게 동작
        LoadScene(sceneName, startDelay);
    }
}
#endregion
