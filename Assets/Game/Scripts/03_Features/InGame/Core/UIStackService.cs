using System.Collections.Generic;
using UnityEngine;
using UnityEngine.InputSystem;
using VContainer.Unity;

public interface IStackablePopup
{
    void ClosePopup();
    bool IsPopupActive();
}

public interface IUIStackService
{
    void Push(IStackablePopup popup);
    void Pop(IStackablePopup popup);
    void Clear();
}

/// <summary>
/// [기능]: 씬 상에 열리는 UI 팝업들을 Stack으로 관리하여 ESC 입력 시 최상단 활성 팝업부터 하나씩 순차적으로 닫아주는 서비스입니다.
/// [작성자]: 윤승종
/// </summary>
public class UIStackService : IUIStackService, ITickable
{
    public static bool IsTestMode = false;
    private readonly Stack<IStackablePopup> m_popupStack = new Stack<IStackablePopup>();

    public void Push(IStackablePopup popup)
    {
        if (popup == null || m_popupStack.Contains(popup))
        {
            return;
        }
        m_popupStack.Push(popup);
        Debug.Log($"[UIStackService] 팝업 추가됨. 현재 스택 수: {m_popupStack.Count}");
    }

    public void Pop(IStackablePopup popup)
    {
        if (m_popupStack.Count == 0)
        {
            return;
        }

        // 최상단이 본인이라면 즉시 제거
        if (m_popupStack.Peek() == popup)
        {
            m_popupStack.Pop();
            Debug.Log($"[UIStackService] 최상단 팝업 제거됨. 현재 스택 수: {m_popupStack.Count}");
            return;
        }

        // 중간 요소일 경우 재정렬
        var tempStack = new Stack<IStackablePopup>();
        while (m_popupStack.Count > 0)
        {
            var top = m_popupStack.Pop();
            if (top != popup)
            {
                tempStack.Push(top);
            }
        }
        while (tempStack.Count > 0)
        {
            m_popupStack.Push(tempStack.Pop());
        }
        Debug.Log($"[UIStackService] 특정 팝업 제거 완료. 현재 스택 수: {m_popupStack.Count}");
    }

    public void Clear()
    {
        m_popupStack.Clear();
    }

    public void Tick()
    {
        if (IsTestMode)
        {
            return;
        }
        var keyboard = Keyboard.current;
        if (keyboard == null || m_popupStack.Count == 0)
        {
            return;
        }

        if (keyboard.escapeKey.wasPressedThisFrame)
        {
            // 스택에서 유효한 팝업 하나씩 꺼내며 닫기 단독 실행
            while (m_popupStack.Count > 0)
            {
                var top = m_popupStack.Peek();
                
                // 가짜 널(MissingReference / Destroyed) 검사 수행
                if (top is MonoBehaviour mono)
                {
                    if (mono == null)
                    {
                        m_popupStack.Pop();
                        continue;
                    }
                }

                if (top != null && top.IsPopupActive())
                {
                    top.ClosePopup();
                    break;
                }
                m_popupStack.Pop();
            }
        }
    }
}
