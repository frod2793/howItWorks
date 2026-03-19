using UnityEngine;
using UnityEngine.UI;

#region 뷰 (View)
/// <summary>
/// [설명]: 타이틀 화면의 버튼 UI를 관리하고 뷰모델 명령과 연결하는 뷰 클래스입니다.
/// </summary>
public class TitleView : MonoBehaviour
{
    #region 에디터 설정
    [Header("Menu Buttons")]
    [SerializeField] private Button m_newGameButton;
    [SerializeField] private Button m_loadGameButton;
    [SerializeField] private Button m_settingsButton;
    [SerializeField] private Button m_archiveButton;
    #endregion

    #region 내부 필드
    private ITitleViewModel m_viewModel;
    private ISoundService m_soundService;
    #endregion

    #region 초기화 및 바인딩 로직
    /// <summary>
    /// [설명]: 뷰모델 및 사운드 서비스를 통해 뷰를 초기화합니다.
    /// </summary>
    public void Initialize(ITitleViewModel viewModel, ISoundService soundService = null)
    {
        if (viewModel == null) return;
        m_viewModel = viewModel;
        m_soundService = soundService;

        // 타이틀 시퀀스 시작 시 BGM 유지 또는 재생
        m_soundService?.PlayBGM("Title/titleSample03", 1.0f);

        // 버튼 이벤트 바인딩
        if (m_newGameButton != null) m_newGameButton.onClick.AddListener(m_viewModel.NewGame);
        if (m_loadGameButton != null) m_loadGameButton.onClick.AddListener(m_viewModel.LoadGame);
        if (m_settingsButton != null) m_settingsButton.onClick.AddListener(m_viewModel.OpenSettings);
        if (m_archiveButton != null) m_archiveButton.onClick.AddListener(m_viewModel.OpenArchive);
    }
    #endregion

    private void OnDestroy()
    {
        if (m_newGameButton != null) m_newGameButton.onClick.RemoveAllListeners();
        if (m_loadGameButton != null) m_loadGameButton.onClick.RemoveAllListeners();
        if (m_settingsButton != null) m_settingsButton.onClick.RemoveAllListeners();
        if (m_archiveButton != null) m_archiveButton.onClick.RemoveAllListeners();
    }
}
#endregion
